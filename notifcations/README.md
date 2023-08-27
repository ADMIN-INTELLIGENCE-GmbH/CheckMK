# General

Since were are using ntfy.sh as our new push service and I couldn't find an appropriate script for I built one myself.

It also has a link to the actual host or service so that you are able to jump directly to that host or service without opening the monitoring and search for the host or service.

<img src="image-2.png" width="800px">

The script is actual work in progress, but it is working fine as for now.

# Installation

Just copy the script to the following folder on your Checkmk server installation and set the executable flag:

~~~
/opt/omd/sites/[sitename]/share/check_mk/notifications
~~~

Now you can select the notifiction type from your settings:

<img src="image.png" width="500px">

# Configuration

To configure the notification method, fill in the first 3 parameters with the following content:

1. Hostname of your ntfy.sh-Server. It needs to be accessible via HTTPS.
2. Channel name created within your ntfy.sh server
3. URL to your monitoring system (only the part before the first "/")

<img src="image-1.png" width="1000px">

# TODOs

- [ ] add "basic auth" for ntfy.sh server