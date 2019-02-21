# Install

## Base Debian 9 Install

- `apt install -y git ruby ruby-dev ruby-bundler build-essential libpq-dev zlib1g-dev postgresql-server-dev-all authbind`
- `apt install -y redis-server postgresql`
- `su - postgres`
- `createuser -P vuln`
- `createdb -O vuln vuln`
- `exit`
- `git clone https://github.com/salesforce/vulnreport`
- `cd vulnreport`
- (Remove Ruby version requirement in Gemfile 
- `bundle install`
- Create a `.env` file that looks like this:
```
export RACK_ENV=production
export VR_SESSION_SECRET=ADD_RANDOM_STRING_HERE
export DATABASE_URL=postgres://vuln:vuln@localhost:5432/vuln
export REDIS_URL=redis://localhost:6379/
export ROLLBAR_ACCESS_TOKEN=[ROLLBAR ACCESS TOKEN HERE]
```
- `openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout server.key -out server.crt`
- `ruby SEED.rb`
- `./start.sh`
