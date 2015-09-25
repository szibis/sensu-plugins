From Sensu plugins elasticache-metrics.rb but with simple modification.

We send metrics with current timestamp for example when we use graphite with faster then 60 seconds timeseries. When we use for example 30 seconds reporting in graphite then we get two same values from plugin but without any null's.
