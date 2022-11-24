require 'benchmark/ips'


# gem "trailblazer-activity-dsl-linear", "1.0.0"


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

[args] becomes ctx in activity
                ruby      1.416M (± 2.5%) i/s -      7.151M in   5.053467s
            activity    215.552k (± 0.7%) i/s -      1.088M in   5.045472s

activity skips Start
              ruby      1.409M (± 1.8%) i/s -      7.111M in   5.049923s
            activity    236.611k (± 0.6%) i/s -      1.199M in   5.065879s

activity 1.0.1
               ruby      1.353M (± 2.2%) i/s -      6.843M in   5.061270s
            activity    230.110k (± 1.0%) i/s -      1.163M in   5.053997s

don't freeze circuit_options in Circuit
                ruby      1.348M (± 2.5%) i/s -      6.794M in   5.043498s
            activity    227.496k (± 5.7%) i/s -      1.151M in   5.079696s

call circuit directly
                ruby      1.346M (± 2.4%) i/s -      6.816M in   5.066014s
            activity    251.755k (± 1.2%) i/s -      1.277M in   5.071317s


=end



class OutPipe < Trailblazer::Activity::Railway

  def self.call_decision(ctx, **options)
    filter = ctx.condition

    signal = filter.(ctx, **options) # circuit-step interface
    return signal ? Trailblazer::Activity::Right : Trailblazer::Activity::Left, ctx
  end

  def self.call_filter(ctx, **options)
    filter = ctx.filter

    signal, _ = filter.(ctx, **options) # circuit-step interface
    ctx[:value] = signal

    return Trailblazer::Activity::Right, ctx
  end

  def self.write_to_aggregate(ctx, **)
    ctx[:aggregate][ctx.write_name] = ctx[:value]
    return Trailblazer::Activity::Right, ctx
  end

  step task: method(:call_decision)
  step task: method(:call_filter)
  step task: method(:write_to_aggregate)


  to_h[:circuit].instance_variable_set(:@start_task, method(:call_decision))
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
  def initialize(condition, filter, write_name)
    super()
    @condition = condition
    @filter = filter
    @write_name = write_name
  end

  attr_reader :condition
  attr_reader :filter
  attr_reader :write_name
end


activity_condition = ->(ctx, **circuit_options) { ctx[:pass] }
activity_filter = ->(ctx, **circuit_options) { ctx[:pass] }

wrap_ctx = HashCtx.new(
  activity_condition,
  activity_filter,
  @write_name
)
wrap_ctx[:aggregate]  = {}
wrap_ctx[:pass]       = true

signa, (ctx, _) = OutPipe.to_h[:circuit].(wrap_ctx)
pp ctx

Benchmark.ips do |x|


  x.report("ruby") {
    wrap_ctx = {aggregate: {}}
    original_args = [[{:pass => true}, 2], {}]

    call_with_decision(wrap_ctx, original_args)
  }

  circuit = OutPipe.to_h[:circuit]

    _wrap_ctx = HashCtx.new(
      activity_condition,
      activity_filter,
      @write_name,
    )
  x.report("activity") {
    _wrap_ctx[:aggregate]  = {}
    _wrap_ctx[:pass]       = true

    _, (ctx, _) = circuit.(_wrap_ctx)
  }

end
