gem "benchmark-ips"
require 'benchmark/ips'


gem "trailblazer-activity-dsl-linear", "1.0.0"

require "trailblazer/activity/dsl/linear"

=begin
WITH STEP INTERFACE
                ruby      1.456M (± 1.7%) i/s -      7.408M in   5.088055s
            activity     92.473k (± 1.8%) i/s -    464.275k in   5.022302s



WITH CIRCUIT INTERFACE
Calculating -------------------------------------
                ruby      1.475M (± 1.9%) i/s -      7.490M in   5.079638s
            activity    192.998k (± 1.3%) i/s -    984.050k in   5.099648s

=end



class OutPipe < Trailblazer::Activity::Railway

  def self.call_decision(args, **options)
    filter = args[0][:decision]

    signal = filter.(args, **options) # circuit-step interface
    return signal ? Trailblazer::Activity::Right : Trailblazer::Activity::Left, args
  end

  def self.call_filter(args, **options)
    filter = args[0][:filter]

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




def call(wrap_ctx, original_args, filter=@filter)
  wrap_ctx = set_variable_for_filter(filter, wrap_ctx, original_args)

  return wrap_ctx, original_args
end

def set_variable_for_filter(filter, wrap_ctx, original_args)
  value = call_filter(filter, wrap_ctx, original_args)

  wrap_ctx[:aggregate][@write_name] = value # yes, we're mutating, but this is ok as we're on some private hash.

  wrap_ctx
end

# Call a filter with a Circuit-Step interface.
def call_filter(filter, wrap_ctx, (args, circuit_options))
  value, _ = filter.(args, **circuit_options) # circuit-step interface
  value
end

def call_with_decision(wrap_ctx, original_args)
  decision, _ = call_filter(@condition, wrap_ctx, original_args)

  return call(wrap_ctx, original_args) if decision
  return wrap_ctx, original_args
end

@condition = ->(args, **circuit_options) { args[0][:pass] }
@filter = ->(args, **circuit_options) { args[0][:pass] }
@write_name = :field

wrap_ctx = {aggregate: {}}
original_args = [[{:pass => true}, 2], {}]
pp call_with_decision(wrap_ctx, original_args)


wrap_ctx = {
  aggregate: {},
  decision: @condition,
  filter: @filter,
  :pass => true,
}
# original_args = [[wrap_ctx, 2], {}]

signa, (ctx, _) = OutPipe.to_h[:activity].([wrap_ctx, {}])
pp ctx

Benchmark.ips do |x|


  x.report("ruby") {
    wrap_ctx = {aggregate: {}}
    original_args = [[{:pass => true}, 2], {}]

    call_with_decision(wrap_ctx, original_args)
  }

  activity = OutPipe.to_h[:activity]

  x.report("activity") {
    wrap_ctx = {
      aggregate: {},
      decision: @condition,
      filter: @filter,
      :pass => true,
    }
    # original_args = [[wrap_ctx, 2], {}]

    _, (ctx, _) = activity.([wrap_ctx, {}])
  }

end
