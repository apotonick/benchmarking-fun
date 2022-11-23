gem "benchmark-ips"
require 'benchmark/ips'

     #   add_variables    281.814k (± 2.4%) i/s -      1.410M in   5.005174s
     #    set_variable    732.820k (± 3.2%) i/s -      3.690M in   5.040353s
     # aggregate_array    457.386k (± 1.8%) i/s -      2.294M in   5.017356s


def add_variables(aggregate, variables)
  aggregate.merge(variables)
end

def set_variable(aggregate, variable_name, value)
  aggregate[variable_name] = value
  aggregate
end

def aggregate_array(aggregate, variable_name, value)
  [variable_name, value]
end




Benchmark.ips do |x|


  x.report("add_variables") {
    aggregate = {}

    15.times do |i|
      aggregate = add_variables(aggregate, {i => i+1})
    end
  }

  x.report("set_variable") {
    aggregate = {}

    15.times do |i|
      aggregate = set_variable(aggregate, i, i+1)
    end
  }


  x.report("aggregate_array") {
    aggregate = {}

    aggregate =
    15.times.collect do |i|
      aggregate_array(aggregate, i, i+1)
    end.to_h
}

end


