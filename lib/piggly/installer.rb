module Piggly
  class Installer
    class << self

      # Compiles the procedures in +file+ with instrumentation and installs them
      def trace_proc(file)
        # recompile with instrumentation if needed
        cache = Piggly::Compiler::Trace.cache(file)

        # install instrumented code
        connection.exec cache['code.sql']

        # map tag messages to tag objects
        Piggly::Profile.add(file, cache['tags'], cache)
      end

      # Reinstalls the original stored procedures in +file+
      def untrace_proc(file)
        connection.exec File.read(file)
      end

      # TODO: not implemented
      def trace(procedure)
        tree = Parser.parse(File.read(procedure_path))

        # recompile with instrumentation
        result = Piggly::Compiler::Trace.compile(tree)
          # tree - tagged and rewritten parse tree
          # tags - collection of Piggly::Tag values in the tree
          # code - instrumented

        connection.exec(procedure.define(result[:code]))
        
        Piggly::Profile.add(procedure, result[:tags])
      end

      # TODO: not implemented
      def untrace(procedure)
        connection.exec(procedure.define)
      end

      # Installs necessary instrumentation support
      def install_trace_support
        # record trace messages
        connection.set_notice_processor(&Piggly::Profile.notice_processor)

        # install tracing functions
        connection.exec <<-SQL
          -- signals that a conditional expression was executed
          CREATE OR REPLACE FUNCTION piggly_cond(message varchar, value boolean)
            RETURNS boolean AS $$
          BEGIN
            IF value THEN
              RAISE WARNING '#{Piggly::Config.trace_prefix} % t', message;
            ELSE
              RAISE WARNING '#{Piggly::Config.trace_prefix} % f', message;
            END IF;
            RETURN value;
          END $$ LANGUAGE 'plpgsql' VOLATILE;
        SQL

        connection.exec <<-SQL
          -- generic signal
          CREATE OR REPLACE FUNCTION piggly_signal(message varchar, signal varchar)
            RETURNS void AS $$
          BEGIN
            RAISE WARNING '#{Piggly::Config.trace_prefix} % %', message, signal;
          END $$ LANGUAGE 'plpgsql' VOLATILE;
        SQL

        connection.exec <<-SQL
          -- signals that a (sub)expression was executed. handles '' and NULL value
          CREATE OR REPLACE FUNCTION piggly_expr(message varchar, value varchar)
            RETURNS varchar AS $$
          BEGIN
            RAISE WARNING '#{Piggly::Config.trace_prefix} %', message;
            RETURN value;
          END $$ LANGUAGE 'plpgsql' VOLATILE;
        SQL

        connection.exec <<-SQL
          -- signals that a (sub)expression was executed. handles all other types
          CREATE OR REPLACE FUNCTION piggly_expr(message varchar, value anyelement)
            RETURNS anyelement AS $$
          BEGIN
            RAISE WARNING '#{Piggly::Config.trace_prefix} %', message;
            RETURN value;
          END $$ LANGUAGE 'plpgsql' VOLATILE;
        SQL

        connection.exec <<-SQL
          -- signals that a branch was taken
          CREATE OR REPLACE FUNCTION piggly_branch(message varchar)
            RETURNS void AS $$
          BEGIN
            RAISE WARNING '#{Piggly::Config.trace_prefix} %', message;
          END $$ LANGUAGE 'plpgsql' VOLATILE;
        SQL
      end

      # Uninstalls instrumentation support
      def uninstall_trace_support
        connection.set_notice_processor
        connection.exec "DROP FUNCTION IF EXISTS piggly_cond(varchar, boolean);"
        connection.exec "DROP FUNCTION IF EXISTS piggly_expr(varchar, varchar);"
        connection.exec "DROP FUNCTION IF EXISTS piggly_expr(varchar, anyelement);"
        connection.exec "DROP FUNCTION IF EXISTS piggly_branch(varchar);"
      end

      # Returns the active PGConn
      def connection
        ActiveRecord::Base.connection.raw_connection
      end

    end
  end
end
