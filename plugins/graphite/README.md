### Graphite fetch data plugin

Install sensu-plugin:

Just git clone or copy to your sensu plugin dir and install dependencies

```
pip install -r requirements.txt
```

What can we do with this plugin:

* Run in python - works faster then ruby versions
* Fetch data from graphite simple target with all functions in graphite with timeouts and retries for increase success
* Specify window of fetching data
* Add some meth methods to fetched data in specified time window - mean, max, min, percentile, last, last-n (minus n points) and more
* Advance alert rules for warnings and criticals with operators like ==, =>, =<, <, >, != and we can use normal integer alert level like in standard plugins
* soon more features

more info run:
```
python graphite.py -h

usage: graphite.py [-h] -t TARGET -e ENDPOINT -i INTERVAL -m METHOD -w WARNING
                   -c CRITICAL

```
optional arguments:
  -h, --help            show this help message and exit
  -t TARGET, --target TARGET
                        The graphite metric name. Can include * to query
                        multiple metrics
  -e ENDPOINT, --endpoint ENDPOINT
                        Graphite query hostname endpoint
  -i INTERVAL, --interval INTERVAL
                        The period back in time to extract from Graphite. Use
                        24hours, 2days, 15mins, etc, same format as in
                        Graphite
  -m METHOD, --method METHOD
                        Option which and how get data from period and what to
                        do with this data. Available: average, mean, last,
                        min, max, percentile<n>, last<n>, example:
                        percentile99
  -w WARNING, --warning WARNING
                        Warning level with use ==, =>, =<, <, >, != example
                        '<= 10' or just 10
  -c CRITICAL, --critical CRITICAL
                        Critical level with use ==, =>, =<, <, >, != example:
                        '>= 11' or just 11
```
