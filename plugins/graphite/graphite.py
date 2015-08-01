#!/usr/bin/python

from sensu_plugin import SensuPluginCheck
import operator as opr
import simplejson as json
import urllib2
import sys
import re
import traceback
import backoff
import numpy

class GraphiteCheck(SensuPluginCheck):
  def setup(self):
    # Setup is called with self.parser set and is responsible for setting up
    # self.options before the run method is called

    # This from graphite metrics check is inspired by ruby version from community-sensu-plugins
    # If you need a fast way to generate alert based on graphite data this is for you.

    self.parser.add_argument(
      '-t',
      '--target',
      required=True,
      help="The graphite metric name. Can include * to query multiple metrics"
    )
    self.parser.add_argument(
      '-e',
      '--endpoint',
      required=True,
      help="Graphite query hostname endpoint"
    )
    self.parser.add_argument(
      '-i',
      '--interval',
      required=True,
      help="The period back in time to extract from Graphite. Use 24hours, 2days, 15mins, etc, same format as in Graphite"
    )
    self.parser.add_argument(
      '-m',
      '--method',
      default="average",
      required=True,
      help="Option which and how get data from period and what to do with this data. Available: average, mean, last, min, max, percentile<n>, last<n>, example: percentile99"
    )
    self.parser.add_argument(
      '-w',
      '--warning',
      required=True,
      type=str,
      help="Warning level with use ==, =>, =<, <, >, != example '<= 10' or just 10"
    )
    self.parser.add_argument(
      '-c',
      '--critical',
      required=True,
      type=str,
      help="Critical level with use ==, =>, =<, <, >, != example: '>= 11' or just 11"
    )
    self.parser.add_argument(
      '-n',
      '--nodata',
      required=False,
      help="Ignore no data - result OK if no data"
    )

  class Methods(object):
     def average(self, datapoints):
         return "%.3f" % numpy.average(datapoints)

     def mean(self, datapoints):
         return "%.3f" % numpy.mean(datapoints)

     def max(self, datapoints):
         return max(datapoints)

     def min(self, datapoints):
         return min(datapoints)

     def last(self, datapoints, number):
         if number == 0:
            return datapoints[-1]
         else:
            return datapoints[number]

     def sum(self, datapoints):
         return sum(datapoints)

     def percentile(self, datapoints, percentile):
         return numpy.percentile(datapoints, percentile)

  @backoff.on_exception(backoff.expo,
                        urllib2.URLError,
                        max_tries=3)
  def get_graphite_data(self):
              resource_url = 'http://' + self.options.endpoint + '/render?format=json&target=' + self.options.target + '&from=-' + self.options.interval
              response = json.loads(urllib2.urlopen(resource_url, timeout = 10).read())
              return response

  def parse_rules(self, ruleopt):
        RLIST = {'==': opr.eq, '>=': opr.ge, '<=': opr.le, '<': opr.lt, '>': opr.gt, '!=': opr.ne}
        try:
            RULE_OP = ruleopt.split(' ')[0]
            RULE_VAR = ruleopt.split(' ')[1]
            operator = RLIST[RULE_OP]
        except:
            operator = None
            RULE_VAR = ruleopt
        return { 'operator': operator, 'value': RULE_VAR, 'input': ruleopt }

  def apply_rules(self, atype, operator, op_value, value):
      if operator is None:
         bool_return = float(value) > float(op_value)
      else:
         bool_return = operator(float(value), float(op_value))
      if not bool_return:
            return 0
      else:
         if "warning" in atype and bool_return:
            return 1
         if "critical" in atype and bool_return:
            return 2

  def get_datapoints(self, response):
      datapoints = []
      return_data = {}
      if response:
         for tar in response:
             target =  tar['target']
             for values in tar['datapoints']:
                 if "None" in str(values[0]):
                    pass
                 else:
                    datapoints.append(values[0])
             return_data[target] = datapoints
             datapoints = []
      return return_data

  def alert_rule(self, compare_warning, compare_critical):
    if compare_warning == 0 and compare_critical == 0:
      return 0
    elif compare_warning == 1 and compare_critical == 0:
      return 1
    elif compare_critical == 2 and compare_warning > 0:
      return 2
    elif compare_critical == 2:
      return 2
    else:
      return None

  def valid_last(self, values, opt_value):
      values_len = int(len(values))
      ops_len = int(abs(opt_value))
      if (values_len < ops_len) or (values_len == ops_len):
          negative = -abs(values_len)
          return negative
      elif values_len > ops_len:
         return opt_value

  def run(self):
    # this method is called to perform the actual check
    self.check_name('Check') # defaults to class name

    try:
       response = self.get_graphite_data()
    except:
       if self.options.nodata:
          self.ok(self.options.target + " OK")
       else:
          self.unknown("No Data or Bad metric")
    targets = self.get_datapoints(response)
    if not targets:
       if self.options.nodata:
          self.ok("OK")
       else:
          self.unknown("No data or Bad metric")
    output = []
    levels = []
    for target in targets:
         percentile_match = re.match( r'(percentile)(.*)', self.options.method)
         last_match = re.match( r'(last)(.*)', self.options.method)
         if percentile_match or last_match:
             method_opts_temp = self.options.method
             if percentile_match:
                method_opts = percentile_match.group(1)
                addvalue = percentile_match.group(2)
             if last_match:
                method_opts = last_match.group(1)
                addvalue = last_match.group(2)
         else:
             method_opts = self.options.method
         try:
           my_class = self.Methods()
           method = getattr(my_class, method_opts)
         except:
            raise Exception("Method (%s) is not implemented" % method_opts)
         if percentile_match or last_match:
            targets_vars = targets.get(target)
            if last_match:
               if not addvalue:
                  addvalue = 0
               addvalue = self.valid_last(targets.get(target), int(addvalue))
            method_value = method(targets_vars, int(addvalue))
         else:
            if targets.get(target):
                method_value = method(targets.get(target))
         wrule = self.parse_rules(self.options.warning)
         crule = self.parse_rules(self.options.critical)
         compare_warning = self.apply_rules("warning", wrule['operator'], wrule['value'], method_value)
         compare_critical = self.apply_rules("critical", crule['operator'], crule['value'], method_value)
         alert_level = self.alert_rule(compare_warning, compare_critical)
         if alert_level == 0:
               levels.append(alert_level)
         elif alert_level == 1:
               levels.append(alert_level)
               output.append(target + " (W) " + str(method_value))
         elif alert_level == 2:
               levels.append(alert_level)
               output.append(target + " (C) " + str(method_value))
         if "OK" not in output:
             message = ', '.join(output)

    if all(i == 0 for i in levels):
      self.ok(self.options.target + " OK")
    elif (1 in levels) and (2 not in levels):
      self.warning(message)
    elif (2 in levels):
      self.critical(message)
    elif self.options.nodata:
      self.ok(self.options.target + " OK")
    else:
      self.unknown(message)

if __name__ == "__main__":
  f = GraphiteCheck()
