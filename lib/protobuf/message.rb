require 'protobuf/message/fields'
require 'protobuf/message/serialization'

# Under MRI, this optimizes proto decoding by around 15% in tests.
# When unavailable, we fall to pure Ruby.
# rubocop:disable Lint/HandleExceptions
begin
  require 'varint/varint'
rescue LoadError
end

begin
  require 'protobuf_java_helpers'
rescue LoadError
end
# rubocop:enable Lint/HandleExceptions

require 'protobuf/varint'

module Protobuf
  class Message

    ##
    # Includes & Extends
    #

    extend ::Protobuf::Message::Fields
    include ::Protobuf::Message::Serialization
    ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::MessageOptions }

    ##
    # Class Methods
    #

    def self.to_json
      name
    end

    def self._protobuf_message_write_nil_method(tag)
      self.class_eval <<-RUBY , __FILE__, __LINE__ + 1
        def _protobuf_message_set_field_#{tag}(*args)
          nil
        end

        def _protobuf_message_set_field_#{tag}_bytes(*args)
          nil
        end
      RUBY
    end

    def self._protobuf_message_write_map_set_method(field)
      self.class_eval <<-RUBY , __FILE__, __LINE__ + 1
        def _protobuf_message_set_field_#{field.name}(field, value, ignore_nil_for_repeated)
          unless value.is_a?(Hash)
            fail TypeError, <<-TYPE_ERROR
                Expected map value
                Got '\#{value.class}' for map protobuf field \#{field.name}
            TYPE_ERROR
          end

          if value.empty?
            @values.delete(:#{field.name})
          else
            @values[:#{field.name}] ||= ::Protobuf::Field::FieldHash.new(field)
            @values[:#{field.name}].replace(value)
          end
        end
      RUBY
    end

    def self._protobuf_message_write_repeated_set_method(field)
      method_def = <<-RUBY
         def _protobuf_message_set_field_#{field.name}(field, value, ignore_nil_for_repeated)
           if value.nil? && ignore_nil_for_repeated
             ::Protobuf.deprecator.deprecation_warning("[#{field.name}]=nil", "use an empty array instead of nil")
             return
           end
           unless value.is_a?(Array)
             fail TypeError, <<-TYPE_ERROR
                 Expected repeated value of type #{field.type_class}
                 Got \#{value.class} for repeated protobuf field #{field.name}
             TYPE_ERROR
           end

           value = value.compact

           if value.empty?
             @values.delete(:#{field.name})
           else
             @values[:#{field.name}] ||= ::Protobuf::Field::FieldArray.new(field)
             @values[:#{field.name}].replace(value)
           end
         end
      RUBY

      self.class_eval method_def, __FILE__, __LINE__ + 1
    end

    def self._protobuf_message_write_set_method(field)
      method_def = <<-RUBY
        def _protobuf_message_set_field_#{field.name}(field, value, ignore_nil_for_repeated)
          if value.nil? # rubocop:disable Style/IfInsideElse
            @values.delete(:#{field.name})
          else
            @values[:#{field.name}] = field.coerce!(value)
          end
        end
      RUBY
      self.class_eval method_def, __FILE__, __LINE__ + 1
    end

    ##
    # Constructor
    #

    def initialize(fields = {})
      @values = {}
      @_tags_to_serialize = ::Set.new
      fields.to_hash.each do |name, value|
        set_field(name, value, true)
      end

      yield self if block_given?
    end

    ##
    # Public Instance Methods
    #

    def clear!
      @values.delete_if do |_, value|
        if value.is_a?(::Protobuf::Field::FieldArray) || value.is_a?(::Protobuf::Field::FieldHash)
          value.clear
          false
        else
          true
        end
      end
      self
    end

    def clone
      copy_to(super, :clone)
    end

    def dup
      copy_to(super, :dup)
    end

    # Iterate over every field, invoking the given block
    #
    def each_field
      return to_enum(:each_field) unless block_given?

      self.class.all_fields.each do |field|
        value = self[field.name]
        yield(field, value)
      end
    end

    def each_field_for_serialization
      self.class.all_fields.each do |field|
        value = @values[field.fully_qualified_name]
        if value.nil?
          fail ::Protobuf::SerializationError, "Required field #{self.class.name}##{field.name} does not have a value." if field.required?
          next
        end
        if field.map?
          # on-the-wire, maps are represented like an array of entries where
          # each entry is a message of two fields, key and value.
          array = Array.new(value.size)
          i = 0
          value.each do |k, v|
            array[i] = field.type_class.new(:key => k, :value => v)
            i += 1
          end
          value = array
        end

        yield(field, value)
      end
    end

#    def field?(name)
#      field = self.class.get_field(name, true)
#      return false if field.nil?
#      if field.repeated?
#        @values.key?(field.fully_qualified_name) && @values[field.fully_qualified_name].present?
#      else
#        @values.key?(field.fully_qualified_name)
#      end
#      @_tags_to_serialize[NAME_TO_TAG[name]]
#    end
#    ::Protobuf.deprecator.define_deprecated_methods(self, :has_field? => :field?)

    def inspect
      attrs = self.class.fields.map do |field|
        [field.name, self[field.name].inspect].join('=')
      end.join(' ')

      "#<#{self.class} #{attrs}>"
    end

    def respond_to_has?(key)
      #respond_to?(key) && field?(key)
      field?(key)
    end
    alias_method :respond_to_has_and_present?, :respond_to_has?

    ##
    # because of the new @values / @_tags_to_encode check we no longer need
    # this as it is the same as `respond_to_has?`
    # def respond_to_has_and_present?(key)
    #   respond_to_has?(key) &&
    #     (self[key].present? || [true, false].include?(self[key]))
    # end

    # Return a hash-representation of the given fields for this message type.
    def to_hash
      result = {}

      @values.each_key do |field_name|
        value = self[field_name]
        field = self.class.get_field(field_name, true)
        hashed_value = value.respond_to?(:to_hash_value) ? value.to_hash_value : value
        result[field.name] = hashed_value
      end

      result
    end

    def to_json(options = {})
      to_json_hash.to_json(options)
    end

    # Return a hash-representation of the given fields for this message type that
    # is safe to convert to JSON.
    def to_json_hash
      result = {}

      @values.each_key do |field_name|
        value = self[field_name]
        field = self.class.get_field(field_name, true)

        # NB: to_json_hash_value should come before json_encode so as to handle
        # repeated fields without extra logic.
        hashed_value = if value.respond_to?(:to_json_hash_value)
                         value.to_json_hash_value
                       elsif field.respond_to?(:json_encode)
                         field.json_encode(value)
                       else
                         value
                       end

        result[field.name] = hashed_value
      end

      result
    end

    def to_proto
      self
    end

    def ==(other)
      return false unless other.is_a?(self.class)
      @values == other.__send__(:instance_variable_get, "@values")
    end

    def [](name)
      field = self.class.get_field(name, true)

      return @values[field.fully_qualified_name] ||= ::Protobuf::Field::FieldHash.new(field) if field.map?
      return @values[field.fully_qualified_name] ||= ::Protobuf::Field::FieldArray.new(field) if field.repeated?
      @values.fetch(field.fully_qualified_name, field.default_value)
    rescue # not having a field should be the exceptional state
      raise if field
      fail ArgumentError, "invalid field name=#{name.inspect}"
    end

    def []=(name, value)
      set_field(name, value, true)
    end

    ##
    # Instance Aliases
    #
    alias :to_hash_value to_hash
    alias :to_json_hash_value to_json_hash
    alias :to_proto_hash to_hash
    alias :responds_to_has? respond_to_has?
    alias :respond_to_and_has? respond_to_has?
    alias :responds_to_and_has? respond_to_has?
    alias :respond_to_has_present? respond_to_has_and_present?
    alias :respond_to_and_has_present? respond_to_has_and_present?
    alias :respond_to_and_has_and_present? respond_to_has_and_present?
    alias :responds_to_has_present? respond_to_has_and_present?
    alias :responds_to_and_has_present? respond_to_has_and_present?
    alias :responds_to_and_has_and_present? respond_to_has_and_present?

    ##
    # Private Instance Methods
    #

    private

    # rubocop:disable Metrics/MethodLength
    def set_field(name, value, ignore_nil_for_repeated)
      #if (field = self.class.get_field(name, true))
        begin
          __send__("_protobuf_message_set_field_#{name}", value, ignore_nil_for_repeated)
          #__send__("_protobuf_message_set_field_#{name}", field, value, ignore_nil_for_repeated)
        rescue NoMethodError => error
          raise unless error.message =~ /_protobuf_message_set_field/i

          case
            when field.map?
              self.class._protobuf_message_write_map_set_method(field)
            when field.repeated?
              self.class._protobuf_message_write_repeated_set_method(field)
            else
              self.class._protobuf_message_write_set_method(field)
          end

          __send__("_protobuf_message_set_field_#{name}", field, value, ignore_nil_for_repeated)
        end
#      else
#        unless ::Protobuf.ignore_unknown_fields?
#          fail ::Protobuf::FieldNotDefinedError, name
#        end
#      end
    end

    def copy_to(object, method)
      duplicate = proc do |obj|
        case obj
        when Message, String then obj.__send__(method)
        else                      obj
        end
      end

      object.__send__(:initialize)
      @values.each do |name, value|
        if value.is_a?(::Protobuf::Field::FieldArray)
          object[name].replace(value.map { |v| duplicate.call(v) })
        else
          object[name] = duplicate.call(value)
        end
      end
      object
    end

  end
end
