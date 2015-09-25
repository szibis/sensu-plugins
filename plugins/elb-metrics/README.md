### ELB handler to send metrics to any other system

elb-metrics.rb from sensu-plugins with some simpler features - works very good with modified graphite.rb handler from https://github.com/szibis/sensu-plugins/tree/master/handlers/graphite/graphite.rb

* You can use this plugin with list of metrics you need. One check for all metrics no need to run many checks on each metric.
* Statistics from default map with fix for SurgeQueueLength - Max -> Maximum
* Loop over all metric you choose and generate output line by line
* Always report metrics with current timestamp fo all that use higher precision then 60 seconds in Cloudwatch - 60 seconds is minimal interval in Cloudwatch. With 30 seconds intervals better to report same value twice then have null's in metrics each each 30 seconds.

#### How-to use with graphite

```json
{
   "checks": {
        "elb_mycheck_name": {
                "type": "metric",
                "handlers": ["graphite_tcp"],
                "command": "AWS_ACCESS_KEY_ID=<aws_key_id> AWS_SECRET_ACCESS_KEY=<<aws_secret_key>> /usr/bin/ruby /etc/sensu/plugins/elb-metrics.rb -n myelb_name -s cloudwatch.elb -f 30 -r us-east-1 -m \"RequestCount,UnHealthyHostCount,HealthyHostCount,HTTPCode_Backend_2XX,HTTPCode_Backend_4XX,HTTPCode_Backend_5XX,HTTPCode_ELB_4XX,HTTPCode_ELB_5XX,BackendConnectionErrors,SurgeQueueLength,SpilloverCount\"",
                "subscribers": ["common",],
                "interval": 30
                }
        }
}
```
You can choose whatever stat you need from Cloudwatch ELB. As example all available on -m example.

More info inside plugin code.

Set handler to send check output from elb-metrics plugin into graphite.
```json
{
  "handlers": {
    "graphite_tcp": {
      "type": "tcp",
      "socket": {
        "host": "127.0.0.1",
        "port": 2013
      },
      "mutator": "only_check_output"
    }
  }
}
```
