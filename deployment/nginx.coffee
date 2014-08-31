fs = require 'fs'

createUpstreams = (workers={}) ->
  upstreams = "# add global upstreams\n"
  for name, options of workers when options.port?
    servers = ""
    {port} = options
    options.instances or= 1
    for index in [0...options.instances]
      servers += "\n" if servers isnt ""
      port = parseInt(port, 10)

      servers += "\tserver 127.0.0.1:#{port + index};"

    upstreams += """
      upstream #{name} {
    #{servers}
      }\n\n"""

  return upstreams



createWebLocation = (name, location) ->
  return """\n
      location #{location} {
        proxy_pass            http://#{name};
        proxy_set_header      X-Real-IP       $remote_addr;
        proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_next_upstream   error timeout   invalid_header http_500;
        proxy_connect_timeout 1;
      }
  \n"""

createWebsocketLocation = (name, location) ->
  return """\n
      location #{location} {
        proxy_pass            http://#{name};
        proxy_http_version    1.1;
        proxy_set_header      Upgrade         $http_upgrade;
        proxy_set_header      Connection      $connection_upgrade;
        proxy_set_header      Host            $host;
        proxy_set_header      X-Real-IP       $remote_addr;
        proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_next_upstream   error timeout   invalid_header http_500;
        proxy_connect_timeout 1;
      }
  \n"""

createUserMachineLocation = (path) ->
  return """\n
      location ~ ^\\/-\\/#{path}\\/(?<ip>.+?)\\/(?<rest>.*) {
        # define our dynamically created backend
        set $backend $ip:3000/$rest;

        # proxy it to the backend
        proxy_pass http://$backend;

        # needed for websocket handshake
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # be a good proxy :)
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_redirect off;

        # Don't buffer WebSocket connections
        proxy_buffering off;

        # Default is 60 seconds, means nginx will close it after 60 seconds
        # inactivity which is a bad thing for long standing connections
        # like websocket. Make it 6 hours.
        proxy_read_timeout 21600s;
        proxy_send_timeout 21600s;
      }
  \n"""

createLocations = (workers={}) ->
  locations = ""
  for name, options of workers when options.port?
    options.nginx = {}  unless options.nginx
    location = ""

    options.nginx.locations or= ["/#{name}"]

    for location in options.nginx.locations
      # if this is a websocket proxy, add required configs
      fn = if options.nginx.websocket
        createWebsocketLocation
      else
        createWebLocation

      locations += fn name, location

  return locations

nginxTemplate = (workers)->


module.exports.create = (workers, environment)->
  config = """
  worker_processes  5;

  #error_log  logs/error.log;
  #error_log  logs/error.log  notice;
  #error_log  logs/error.log  info;

  pid #{if environment is 'dev' then '/usr/local/var/run/nginx.pid' else '/var/run/nginx.pid'};

  events { worker_connections  1024; }

  # start http
  http {

    #{createUpstreams(workers)}

    map $http_upgrade $connection_upgrade { default upgrade; '' close; }

    gzip on;
    gzip_disable "msie6";

    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;

    # start server
    server {
      # do not add hostname here!
      listen #{if environment is "dev" then 8090 else 80};
      root /usr/share/nginx/html;
      index index.html index.htm;
      location = /healthcheck {
        return 200;
        #access_log off;
      }
      #{createLocations(workers)}
      #{createUserMachineLocation("userproxy")}
    # close server
    }
  # close http
  }
  """
  fs.writeFileSync "./deployment/generated_files/nginx.conf", config
  return config
