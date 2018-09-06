require "../../spec_helper"

module Ameba
  private def create_todo
    file = IO::Memory.new
    formatter = Formatter::TODOFormatter.new IO::Memory.new, file

    s = Source.new "a = 1", "source.cr"
    s.add_issue DummyRule.new, {1, 2}, "message"

    formatter.finished [s]
    file.to_s
  end

  describe Formatter::TODOFormatter do
    context "problems not found" do
      it "does not create todo" do
        file = IO::Memory.new
        formatter = Formatter::TODOFormatter.new IO::Memory.new, file
        formatter.finished [Source.new ""]
        file.to_s.empty?.should be_true
      end
    end

    context "problems found" do
      it "creates a valid YAML document" do
        YAML.parse(create_todo).should_not be_nil
      end

      it "creates a todo with header" do
        create_todo.should contain "# This configuration file was generated by"
      end

      it "creates a todo with UTC time" do
        create_todo.should match /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/
      end

      it "creates a todo with version" do
        create_todo.should contain "Ameba version #{VERSION}"
      end

      it "creates a todo with a rule name" do
        create_todo.should contain "DummyRule"
      end

      it "creates a todo with problems count" do
        create_todo.should contain "Problems found: 1"
      end

      it "creates a todo with run details" do
        create_todo.should contain "Run `ameba --only #{DummyRule.rule_name}`"
      end

      it "excludes source from this rule" do
        create_todo.should contain "Excluded:\n  - source.cr"
      end

      context "when invalid syntax" do
        it "does not exclude Syntax rule" do
          file = IO::Memory.new
          formatter = Formatter::TODOFormatter.new IO::Memory.new, file

          s = Source.new "def invalid_syntax"
          s.add_issue Rule::Lint::Syntax.new, {1, 2}, "message"

          formatter.finished [s]
          content = file.to_s

          content.should_not contain "Syntax"
        end
      end
    end
  end
end
