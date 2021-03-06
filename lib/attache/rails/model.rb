require "cgi"
require "uri"
require "httpclient"
require "attache/api"

module Attache
  module Rails
    module Model
      include Attache::API::Model

      def self.included(base)
        # has_one_attache, has_many_attaches
        base.extend ClassMethods

        # `discard` management
        base.class_eval do
          attr_accessor :attaches_to_backup
          attr_accessor :attaches_discarded
          after_commit do |instance|
            instance.attaches_discard!(instance.attaches_discarded) if instance.attaches_discarded.present?
            instance.attaches_discarded = []
            instance.attaches_backup!(instance.attaches_to_backup) if instance.attaches_to_backup.present?
            instance.attaches_to_backup = []
          end
        end
      end

      module ClassMethods
        def attache_setup_column(name)
          case coltype = column_for_attribute(name).type
          when :text, :string, :binary
            serialize name, JSON
          end
        rescue Exception
        end

        def has_one_attache(name)
          attache_setup_column(name)
          define_method "#{name}_options",    -> (geometry, options = {}) { Hash(class: 'enable-attache', multiple: false).merge(attache_field_options(self.send(name), geometry, options)) }
          define_method "#{name}_url",        -> (geometry)               { attache_field_urls(self.send(name), geometry).try(:first) }
          define_method "#{name}_attributes", -> (geometry)               { attache_field_attributes(self.send(name), geometry).try(:first) }
          define_method "#{name}=",           -> (value)                  { super(attache_field_set(Array.wrap(value)).try(:first)) }
          after_save                          ->                          { attache_update_pending_diffs(self.send("#{name}_was"), self.send("#{name}"), self.attaches_to_backup ||= [], self.attaches_discarded ||= []) }
          after_destroy                       ->                          { attache_update_pending_diffs(self.send("#{name}_was"), [], self.attaches_to_backup ||= [], self.attaches_discarded ||= []) }
        end

        def has_many_attaches(name)
          attache_setup_column(name)
          define_method "#{name}_options",    -> (geometry, options = {}) { Hash(class: 'enable-attache', multiple: true).merge(attache_field_options(self.send(name), geometry, options)) }
          define_method "#{name}_urls",       -> (geometry)               { attache_field_urls(self.send(name), geometry) }
          define_method "#{name}_attributes", -> (geometry)               { attache_field_attributes(self.send(name), geometry) }
          define_method "#{name}=",           -> (value)                  { super(attache_field_set(Array.wrap(value))) }
          after_save                          ->                          { attache_update_pending_diffs(self.send("#{name}_was"), self.send("#{name}"), self.attaches_to_backup ||= [], self.attaches_discarded ||= []) }
          after_destroy                       ->                          { attache_update_pending_diffs(self.send("#{name}_was"), [], self.attaches_to_backup ||= [], self.attaches_discarded ||= []) }
        end
      end
    end
  end
end

ActiveRecord::Base.send(:include, Attache::Rails::Model)
