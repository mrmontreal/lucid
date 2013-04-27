require 'optparse'

module Spec #:nodoc:
  module Runner #:nodoc:
    # This makes sure that RSpec's option parser does not kick in.
    # RSpec's option parser tries to parse ARGV, and that will
    # fail when running Lucid.
    class OptionParser < ::OptionParser #:nodoc:
      NEUTERED_RSPEC = Object.new
      def NEUTERED_RSPEC.method_missing(m, *args); self; end

      def self.method_added(m)
        unless @__neutering_rspec
          @__neutering_rspec = true
          define_method(m) do |*a|
            NEUTERED_RSPEC
          end
          @__neutering_rspec = false
        end
      end
    end
  end
end
