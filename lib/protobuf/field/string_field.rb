require 'protobuf/field/bytes_field'

module Protobuf
  module Field
    class StringField < BytesField

      ##
      # Constants
      #

      ENCODING = Encoding::UTF_8

      ##
      # Public Instance Methods
      #

      def acceptable?(val)
        val.is_a?(String) || val.nil? || val.is_a?(Symbol)
      end

      def coerce!(value)
        if value.nil?
          nil
        else
          value.to_s
        end
      end

      def decode(bytes)
        bytes.force_encoding(::Protobuf::Field::StringField::ENCODING)
        bytes
      end

      def encode(value)
        value_to_encode = "" + value # dup is slower
        unless value_to_encode.encoding == ENCODING
          value_to_encode.encode!(::Protobuf::Field::StringField::ENCODING, :invalid => :replace, :undef => :replace, :replace => "")
        end
        value_to_encode.force_encoding(::Protobuf::Field::BytesField::BYTES_ENCODING)

        "#{::Protobuf::Field::VarintField.encode(value_to_encode.size)}#{value_to_encode}"
      end

      def json_encode(value)
        value
      end
    end
  end
end
