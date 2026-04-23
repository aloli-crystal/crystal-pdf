require "../spec_helper"

describe PDF::SVG::PathParser do
  describe ".parse" do
    it "parses a simple move + line-to" do
      commands = PDF::SVG::PathParser.parse("M10 20 L30 40")
      commands.size.should eq(2)
      commands[0].type.should eq('M')
      commands[0].args.should eq([10.0, 20.0])
      commands[1].type.should eq('L')
      commands[1].args.should eq([30.0, 40.0])
    end

    it "parses compact paths with implicit line-to after move" do
      commands = PDF::SVG::PathParser.parse("M0 0 h640 v480 H0 Z")
      # h640 -> L(640, 0), v480 -> L(640, 480), H0 -> L(0, 480), Z
      commands.size.should eq(5)
      commands[0].type.should eq('M')
      commands[-1].type.should eq('Z')
    end

    it "handles numbers separated only by a sign character (no space)" do
      # e.g. `M10 20-5-5` means: move to (10, 20), then implicit line-to
      # at relative (-5, -5) — the signs act as separators.
      commands = PDF::SVG::PathParser.parse("m10 20-5-5")
      commands.size.should eq(2)
      commands[0].type.should eq('M')
      commands[0].args.should eq([10.0, 20.0])
      commands[1].type.should eq('L')
      commands[1].args[0].should eq(5.0)
      commands[1].args[1].should eq(15.0)
    end

    it "terminates on paths that chain end-of-number '.' with start-of-next '.' (regression)" do
      # `4.4.8` should tokenize as [4.4, .8]. Before the fix, the inner
      # number-parsing loop would break on the same '.' it was sitting
      # on (because has_dot had just been set true by the starting '.'),
      # leaving the outer loop stuck on the same byte and spinning
      # forever. This kind of pattern is common in compact flag SVGs.
      commands = PDF::SVG::PathParser.parse("M0 0l4.4.8z")
      commands.size.should be >= 2
    end

    it "parses the Brazil flag path that used to loop forever (regression)" do
      # The 4th path of flag-icons' br.svg stars pattern, reduced for
      # the test: several compact numbers with touching '.' separators.
      d = "m283.3 316.3-4-2.3-4 2 .9-4.5-3.2-3.4 4.5-.5 2.2-4 1.9 4.2 4.4.8-3.3 3"
      commands = PDF::SVG::PathParser.parse(d)
      # The original bug was an infinite loop; any non-empty result
      # is enough to prove we terminate.
      commands.should_not be_empty
    end
  end
end
