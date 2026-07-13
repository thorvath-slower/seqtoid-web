module Types
  # Mirrors the federation mesh `JSON` scalar (CZID-285). Passthrough coercion:
  # arbitrary JSON values (numbers, strings, booleans, arrays, objects, null)
  # round-trip unchanged, matching the REST payloads the federation forwarded.
  class JsonScalar < Types::BaseScalar
    graphql_name "JSON"

    def self.coerce_input(value, _context)
      value
    end

    def self.coerce_result(value, _context)
      value
    end
  end
end
