# Vulnreport
### Pentesting management and automation platform

Vulnreport is a platform for managing penetration tests and generating well-formatted, actionable findings reports without the normal overhead that takes up security engineer's time. The platform is built to support automation at every stage of the process and allow customization for whatever other systems you use as part of your pentesting process.

Vulnreport was built by the Salesforce Product Security team as a way to get rid of the time we spent writing, formatting, and proofing reports for penetration tests. Our goal was and continues to be to build great security tools that let pentesters and security engineers focus on finding and fixing vulns.

For full documentation, see <http://vulnreport.io/documentation>

## Deployment

Vulnreport is a Ruby web application (Sinatra/Rack stack) backed by a PostgreSQL database with a Redis cache layer.

Vulnreport can be installed on a local VM or server behind something like nginx, or can be deployed to [Heroku](https://heroku.com).

### Local Deploy / Your own server

To deploy locally, you'll need to make sure you have installed the dependancies:
* Ruby >= 2.1
* PostgreSQL
* Redis
* Rollbar
* Bundler

Clone the repo and open up the .env file, updating it as necessary. The run `bundle install`. You'll probably want to modify `start.sh` to make it work for your environment - the one included in the repo is intended to be used for local use during debugging/development.

You should also create a .env file based on .env.example, or set the same ENV variables defined in .env in your environment.

### Heroku Deploy

#### Automatic Deployment

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

You can automatically deploy to Heroku. After doing so, follow the instructions below to login to Vulnreport and finish configuration.

#### Manual Deployment

To deploy to Heroku (assuming you have created a Heroku app and have the toolbelt installed)

```sh
git clone [Vulnreport repo url]

heroku git:remote -a [Heroku app name]

heroku addons:create heroku-postgresql:hobby-dev
heroku addons:create heroku-redis:hobby-dev
heroku addons:create rollbar:free
heroku addons:create sendgrid:starter
```

You'll then want to open up the .env file and copy the keys/values (updating values where necessary) to the Heroku settings for your app. This can also be done via the toolbelt CLI commands. Note that the default ENV variables after running the addons should be fine, but you can double check. You'll definitely want to update `VR_SESSION_SECRET`. If this isn't your production install, you should change `RACK_ENV` to `development`.

```sh
heroku config:set VR_SESSION_SECRET=abc123456
heroku config:set RACK_ENV=production

git push heroku master
```

You can now follow the instructions for installation as you would if you were running Vulnreport locally.

## Installation

To handle the initial configuration for Vulnreport, run the `SEED.rb` script. If you are deploying on Heroku, run this via `heroku run ./SEED.rb`.

If you used the automated 'Deploy to Heroku' feature, this step should have been handled for you automatically.

```
Running ./SEED.rb on ⬢ vulnreport-test... up, run.8035

Vulnreport 3.0.0.alpha seed script
WARNING: This script should be run ONCE immediately after deploying and then DELETED

Setting up Vulnreport now...

Setting up the PostgreSQL database...
	Done

Seeding the database...
	Done

User ID 1 created for you


ALL DONE! :)
Login to Vulnreport now and go through the rest of the settings!

```

Now, delete the SEED.rb file.

The default admin user has been created for you with username `admin` and password `admin`. This should be **immediately rotated and/or SSO should be configured.**

At this point you should go to your Vulnreport URL (e.g. https://my-vr-test.herokuapp.com above) and login with the user created. Go through the Vulnreport and user settings to configure your instance of Vulnreport.

## Pentest!

You're ready to go - for documentation about how to use your newly-installed Vulnreport instance, see the full docs at <http://vulnreport.io/documentation>

## Custom Interfaces and Integrations

Vulnreport is designed and intended to be used with external systems. For more information about how to implement the interfaces that allow for integration/synchronization with external systems please see the custom interfaces documentation at <http://vulnreport.io/documentation#interfaces>.

## Code Documentation

To generate the documentation for the code, simply run Yard:
```sh
yard doc
yard server
```