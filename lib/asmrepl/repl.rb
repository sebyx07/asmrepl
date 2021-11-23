require "fiddle"
require "fisk/helpers"
require "crabstone"
require "reline"
require "asmrepl/macos"

class Crabstone::Binding::Instruction
  class << self
    alias :old_release :release
  end

  # Squelch error in crabstone
  def self.release obj
    nil
  end
end

module ASMREPL
  class REPL
    include Fiddle

    CFuncs = MacOS

    def initialize
      size = 1024 * 16 # 16k is enough for anyone!
      @buffer = CFuncs.jitbuffer(size)
      CFuncs.memset(@buffer.memory, 0xCC, size)
      @parser    = ASMREPL::Parser.new
      @assembler = ASMREPL::Assembler.new
    end

    def display_state state
      puts " CPU STATE ".center(48, "=")
      puts state
      puts
      puts "FLAGS: #{state.flags.inspect}"
      puts
    end

    def start
      pid = fork {
        raise unless CFuncs.ptrace(CFuncs::PT_TRACE_ME, 0, 0, 0).zero?
        @buffer.to_function([], TYPE_INT).call
      }

      tracer = CFuncs::Tracer.new pid
      should_cpu = true
      while tracer.wait
        state = tracer.state

        # Show CPU state once on boot
        if should_cpu
          display_state state
          should_cpu = false
        end

        # Move the JIT buffer to the current instruction pointer
        pos = (state.rip - @buffer.memory.to_i)
        @buffer.seek pos
        use_history = true
        loop do
          cmd = nil
          text = Reline.readmultiline(">> ", use_history) do |multiline_input|
            if multiline_input =~ /\A\s*(\w+)\s*\Z/
              register = $1
              cmd = [:read, register]
            else
              cmd = :run
            end
            true
          end

          case cmd
          in :run
            break if text.chomp.empty?
            binary = @assembler.assemble @parser.parse text.chomp
            binary.bytes.each { |byte| @buffer.putc byte }
            break
          in [:read, "cpu"]
            display_state state
          in [:read, reg]
            puts sprintf("%#018x", state[reg])
          else
          end
        end
        tracer.continue
      end
    end
  end
end
