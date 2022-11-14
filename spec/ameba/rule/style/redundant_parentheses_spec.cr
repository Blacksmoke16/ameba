require "../../../spec_helper"

module Ameba::Rule::Style
  subject = RedundantParentheses.new

  describe RedundantParentheses do
    {% for keyword in %w(if unless while until) %}
      context "{{ keyword.id }}" do
        it "reports if redundant parentheses are found" do
          source = expect_issue subject, <<-CRYSTAL, keyword: {{ keyword }}
            %{keyword}   (foo > 10)
            _{keyword} # ^^^^^^^^^^ error: Redundant parentheses
              foo
            end
            CRYSTAL

          expect_correction source, <<-CRYSTAL
            {{ keyword.id }}   foo > 10
              foo
            end
            CRYSTAL
        end
      end
    {% end %}

    context "case" do
      it "reports if redundant parentheses are found" do
        source = expect_issue subject, <<-CRYSTAL
          case (foo = @foo)
             # ^^^^^^^^^^^^ error: Redundant parentheses
          when String then "string"
          when Symbol then "symbol"
          end
          CRYSTAL

        expect_correction source, <<-CRYSTAL
          case foo = @foo
          when String then "string"
          when Symbol then "symbol"
          end
          CRYSTAL
      end
    end

    context "properties" do
      context "#exclude_ternary=" do
        it "skips ternary control expressions by default" do
          expect_no_issues subject, <<-CRYSTAL
            (foo > bar) ? true : false
            CRYSTAL
        end

        it "allows to configure assignments" do
          rule = Rule::Style::RedundantParentheses.new
          rule.exclude_ternary = false

          expect_issue rule, <<-CRYSTAL
            (foo > bar) ? true : false
            # ^^^^^^^^^ error: Redundant parentheses
            CRYSTAL

          expect_no_issues subject, <<-CRYSTAL
            (foo && bar) ? true : false
            CRYSTAL

          expect_no_issues subject, <<-CRYSTAL
            (foo || bar) ? true : false
            CRYSTAL
        end
      end

      context "#exclude_assignments=" do
        it "reports assignments by default" do
          expect_issue subject, <<-CRYSTAL
            if (foo = @foo)
             # ^^^^^^^^^^^^ error: Redundant parentheses
              foo
            end
            CRYSTAL
        end

        it "allows to configure assignments" do
          rule = Rule::Style::RedundantParentheses.new
          rule.exclude_assignments = true

          expect_no_issues rule, <<-CRYSTAL
            if (foo = @foo)
              foo
            end
            CRYSTAL
        end
      end
    end
  end
end
