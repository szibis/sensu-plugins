### Improved mailer handler with advance options

##### Dependencies:

```bash
gem install mail erubis aws-sdk securerandom timeout http
```

##### Features

* send text or html mail
* some advance options based and only on python graphite plugin - https://github.com/szibis/sensu-plugins
* body templates default or use per check template
  * use mail_body in check with your erubis template to everride default template
  * use predefined template values to extend emails:
    * name
    * alertui
    * source
    * timestamp
    * address
    * status
    * occurrences
    * interval
    * duration
    * command
    * checkoutput
    * playbook
    * target
    * warning
    * critical
    * imgurl
    * imginclude
    * linkfooter
* images in mail generated and stored on S3
* link to uchiwa specific alert
* link to graphite-web specific target with warning/critical thresholds

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
