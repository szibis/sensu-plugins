### From Sensu plugins elasticache-metrics.rb but with simple modification.

We send metrics with current timestamp for example when we use graphite with faster then 60 seconds timeseries. When we use for example 30 seconds reporting in graphite then we get two same values from plugin but without any null's.

#### How-to use with graphite

```json
{
   "checks": {
        "elasticache_mycheck_name": {
                "type": "metric",
                "handlers": ["graphite_tcp"],
                "command": "AWS_ACCESS_KEY_ID=<aws_key_id> AWS_SECRET_ACCESS_KEY=<aws_secret_key> /usr/bin/ruby /etc/sensu/plugins/elasticache-metrics.rb -n myelasticache_name -s cloudwatch.myelb_name -f 300 -r us-east-1 -c memcached -i 0001",
                "subscribers": ["common",],
                "interval": 30
                }
        }
}
```
Almost same for redis type elasticache. More info inside plugin code.

Set handler to send check output from elasticache-metrics plugin into graphite.
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
