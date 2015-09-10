### Improved mailer handler with advance options

##### Dependencies:

```bash
gem install mail erubis aws-sdk securerandom timeout http
```

##### Features

* send text or html mail
* some advance options based and only on python graphite plugin - https://github.com/szibis/sensu-plugins
* body and subject templated from default or use per check template override
  * use mail_body in check with your erubis template to everride default template
  * use mail_mode to choose html or plain mode
  * use event hahshes to template values and extend emails - https://sensuapp.org/docs/0.20/api-events:
      * check - hash from all values from event check section - example: check['name']
      * client - hash from all values from event check section - example: client['address']
  * adding more custom values to template:
      * id - event id
      * check_name - check name with removed _ and/or .
      * source_name - check name with removed _ and/or .
      * occurrences - number of event occurrences
      * action - event action
      * alertui - your uchiwa or any other alert ui for event
      * time - time of this event
      * status - string status of this event
      * duration - alert duration
      * nopasscommand - command with no passwords
      * nopasscheckout - check output with no passwords
      * playbook - playbook for your wiki, docs, tips&tricks, knowledge, info
      * target - graphite tagrget source in this event
      * warning - warning level for this even
      * critical - critical level for this event
      * imgurl - url from s3 for image in mail to use
      * imginclude - full <a href....> section prepared to include
      * linkfooter - link footer with graphite alert graph image and your ui alert link
      * bgcolor - predefined bgcolours for resolved, warning, critical and no data
* images in mail contains warning/critical thresholds as horizontal lines
* images in mail generated from graphite and then stored on S3 with link to graphite on image
* link to uchiwa specific alert
* link to graphite-web specific target with warning/critical thresholds generated live from graphite

##### Configuration

New config options for s3 bucket options, graphiteendpoint and uchiwa endpoint

```json
{
    "mailer": {
        "admin_gui": "",
        "mail_from": "",
        "mail_to": "",
        "smtp_address": "localhost",
        "smtp_domain": "local",
        "smtp_port": "25"
        "s3_key": "<you s3 api key>",
        "s3_secret": "<your s3 secret for key>",
        "s3_bucket": "<your s3 bucket name>",
        "s3_bucket_region": "<s3 bucket region>",
        "graphite_endpoint_private": "http://graphite.local",
        "graphite_endpoint_public": "https://graphite.example.com",
        "uchiwa_endpoint_public": "https://uchiwa.example.com"
    }
}
```
