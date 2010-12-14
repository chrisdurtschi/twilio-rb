require 'active_support/core_ext/string' # Chill! we only use the bits of AS we need!

module Twilio
  module Resource
    def initialize(attrs ={})  #:nodoc:
      @attributes = Hash[attrs.map { |k,v| [k.to_s.camelize, v.to_s] }]
    end

    # Convenience for accessing attributes. Attributes can be accessed either using the
    # preferred symbol style, e.g. :if_machine or using the Twilio stringified attribute
    # style, e.g. 'IfMachine'
    # Kind of like ActiveSupport::HashWithIndifferentAccess on crack.
    def [](key)
      accessor = key.is_a?(Symbol) ? key.to_s.camelize : key
      attributes[accessor]
    end

    def []=(key,value)
      accessor = key.is_a?(Symbol) ? key.to_s.camelize : key
      attributes[accessor] = value
    end

    private

    def handle_response(res) # :nodoc:
      if (400..599).include? res.code
        raise Twilio::APIError.new "Error ##{res.parsed_response['code']}: #{res.parsed_response['message']}"
      else
        @attributes.update Hash[res.parsed_response.map { |k,v| [k.camelize, v] }] # params are camelized in requests, yet underscored in the repsonse. inconsistency FTW!
      end
    end

    def method_missing(id, *args, &blk) #:nodoc
      meth = id.to_s
      if meth =~ /\=$/
        add_attr_writer meth
        send meth, args.first
      elsif meth =~ /^#{meth}\?/i
        add_predicate meth
        send meth
      elsif self[id]
        add_attr_reader meth
        send meth
      else
        super
      end
    end

    def add_predicate(attribute)
      metaclass.class_eval do
        define_method(attribute) { self[:status] =~ /^#{attribute.gsub '?', ''}/i ? true : false }
      end
    end

    def add_attr_writer(attribute) #:nodoc
      metaclass.class_eval do
        define_method(attribute) { |value| self[attribute.to_s.gsub(/\=$/, '').to_sym] = value } unless respond_to? attribute
      end
    end

    def add_attr_reader(attribute) #:nodoc
      metaclass.class_eval do
        define_method(attribute) { self[attribute.to_sym] } unless respond_to? attribute
      end
    end

    def metaclass #:nodoc
      class << self; self; end
    end

    def self.included(base)
      base.instance_eval do
        include HTTParty
        attr_reader :attributes
        format      :json
        base_uri    Twilio::API_ENDPOINT
      end

      class << base
        if instance_of? Class # Don't want this mixed into singleton objects e.g. Twilio::Account
          def find(id)
            # All Twilio resources follow a convention, except SMS :(
            klass_name = name.demodulize
            resource = klass_name == 'SMS' ? "#{klass_name}/Messages" : klass_name.pluralize
            res = get "/Accounts/#{Twilio::ACCOUNT_SID}/#{resource}/#{id}.json"
            new Hash[res.parsed_response.map { |k,v| [k.camelize, v] }] if (200..299).include? res.code
          end

          def create(attrs={})
            new(attrs).tap { |c| c.save }
          end 
        end

        # decorate http methods with authentication
        %w<post get put delete>.each do |meth| 
          define_method(meth) do |*args| # splatted args necessary hack since <= 1.8.7 does not support optional block args 
            opts = args[1] || {}
            super args.first, opts.merge(:basic_auth => { :username => Twilio::ACCOUNT_SID, :password => Twilio::AUTH_TOKEN })
          end
        end
      end
    end
  end
end
