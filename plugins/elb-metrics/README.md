### ELB handler to send metrics to any other system

elb-metrics.rb from sensu-plugins with some simpler features - works very good with modified graphite.rb handler from https://github.com/szibis/sensu-plugins/tree/master/handlers/graphite/graphite.rb

* You can use this plugin with list of metrics you need. One check for all metrics no need to run many checks on each metric.
* Statistics from default map with fix for SurgeQueueLength - Max -> Maximum
* Loop over all metric you choose and generate output line by line
* Always report metrics with current timestamp fo all that use higher precision then 60 seconds in Cloudwatch - 60 seconds is minimal interval in Cloudwatch. With 30 seconds intervals better to report same value twice then have null's in metrics each each 30 seconds.

