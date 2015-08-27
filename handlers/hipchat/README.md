### Sensu hipchat handler with advance options for graphite

Based on standard sensu hipchat handler and for now work only with python graphite plugin

Added features:

* Add images rendered from graphite to hipchat message
* Images from graphite in message with warning/critical level lines
* Mini PNG generated from graphite included in hipchat message uploaded to s3 bucket for history
  * You can use Glacier archive after some time
  * Stored in day/hour folders inside defined bucket
* Added link to graphite image - image click and link
* Added Uchiwa link to our alert
* Output modes with simple html templates:
  * minimal (no images minimal info)
  * normal (image + extended info)
  * full (image + much more extended info)
* Info about alert duration
* Info about each target alert level, alert code
* Info about current target and warning/critical levels
* Playbook variable support in advance mode for graphite (add your procedures or wiki links)
