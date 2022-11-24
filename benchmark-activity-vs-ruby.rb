gem "benchmark-ips"
require 'benchmark/ips'


gem "trailblazer-activity-dsl-linear", "1.0.0"

require "trailblazer/activity/dsl/linear"

=begin
WITH STEP INTERFACE
                ruby      1.456M (± 1.7%) i/s -      7.408M in   5.088055s
            activity     92.473k (± 1.8%) i/s -    464.275k in   5.022302s


WITH CIRCUIT INTERFACE
                ruby      1.475M (± 1.9%) i/s -      7.490M in   5.079638s
            activity    192.998k (± 1.3%) i/s -    984.050k in   5.099648s


WITH CALLING :activity DIRECTLY
                ruby      1.381M (± 4.1%) i/s -      6.924M in   5.022472s
            activity    201.448k (± 6.4%) i/s -      1.017M in   5.070345s

WITH ctx.condition instead of {ctx[:condition]}
                ruby      1.470M (± 2.8%) i/s -      7.397M in   5.034842s
            activity    207.621k (± 1.8%) i/s -      1.046M in   5.040922s

CLASS METHODS for ruby
                ruby      1.444M (± 1.7%) i/s -      7.270M in   5.034511s
            activity    213.309k (± 0.6%) i/s -      1.072M in   5.025854s

set_variable for ruby
                ruby      1.398M (± 1.8%) i/s -      7.095M in   5.077891s
            activity    213.497k (± 1.4%) i/s -      1.089M in   5.099665s


=end



class OutPipe < Trailblazer::Activity::Railway

  def self.call_decision(args, **options)
    filter = args[0].condition

    signal = filter.(args, **options) # circuit-step interface
    return signal ? Trailblazer::Activity::Right : Trailblazer::Activity::Left, args
  end

  def self.call_filter(args, **options)
    filter = args[0].filter

    signal, _ = filter.(args, **options) # circuit-step interface
    args[0][:value] = signal

    return Trailblazer::Activity::Right, args
  end

  def self.write_to_aggregate(args, **)
    args[0][:aggregate][@write_name] = args[0][:value]
    return Trailblazer::Activity::Right, args
  end

  step task: method(:call_decision)
  step task: method(:call_filter)
  step task: method(:write_to_aggregate)
end



module Runtime
  def self.call(wrap_ctx, original_args, filter, write_name)
    wrap_ctx = set_variable_for_filter(filter, write_name, wrap_ctx, original_args)

    return wrap_ctx, original_args
  end

  def self.set_variable_for_filter(filter, write_name, wrap_ctx, original_args)
    value = call_filter(filter, wrap_ctx, original_args)

    wrap_ctx = set_variable(write_name, value, wrap_ctx, original_args)
    wrap_ctx
  end

  # Call a filter with a Circuit-Step interface.
  def self.call_filter(filter, wrap_ctx, (args, circuit_options))
    value, _ = filter.(args, **circuit_options) # circuit-step interface
    value
  end

  def self.set_variable(write_name, value, wrap_ctx, original_args)
    wrap_ctx[:aggregate][write_name] = value # yes, we're mutating, but this is ok as we're on some private hash.
    wrap_ctx
  end
end

def call_with_decision(wrap_ctx, original_args)
  decision, _ = Runtime.call_filter(@condition, wrap_ctx, original_args)

  return Runtime.call(wrap_ctx, original_args, @filter, @write_name) if decision
  return wrap_ctx, original_args
end

@condition = ->(args, **circuit_options) { args[0][:pass] }
@filter = ->(args, **circuit_options) { args[0][:pass] }
@write_name = :field

wrap_ctx = {aggregate: {}}
original_args = [[{:pass => true}, 2], {}]
pp call_with_decision(wrap_ctx, original_args)


class HashCtx < Hash
  def initialize(condition, filter)
    super()
    @condition = condition
    @filter = filter
  end

  attr_reader :condition
  attr_reader :filter
end

wrap_ctx = HashCtx.new(
  @condition,
  @filter
)
wrap_ctx[:aggregate]  = {}
wrap_ctx[:pass]       = true

signa, (ctx, _) = OutPipe.to_h[:activity].([wrap_ctx])
pp ctx

Benchmark.ips do |x|


  x.report("ruby") {
    wrap_ctx = {aggregate: {}}
    original_args = [[{:pass => true}, 2], {}]

    call_with_decision(wrap_ctx, original_args)
  }

  activity = OutPipe.to_h[:activity]

    _wrap_ctx = HashCtx.new(
      @condition,
      @filter
    )
  x.report("activity") {
    _wrap_ctx[:aggregate]  = {}
    _wrap_ctx[:pass]       = true

    _, (ctx, _) = activity.([_wrap_ctx ])
  }

end
