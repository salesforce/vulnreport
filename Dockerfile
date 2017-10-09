FROM ruby:2.1.2

ENV INSTALL_PATH /home
RUN mkdir -p $INSTALL_PATH

WORKDIR $INSTALL_PATH

RUN apt-get update &&  apt-get install -y wget
RUN touch /etc/apt/sources.list.d/pgdg.list
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main" >> /etc/apt/sources.list.d/pgdg.list
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update && apt-get install -y postgresql-9.3 postgresql-server-dev-9.3 libpq-dev authbind

COPY Gemfile Gemfile
RUN bundle install

COPY . .

RUN ./.env

ENTRYPOINT ["/bin/bash","start.sh"]
