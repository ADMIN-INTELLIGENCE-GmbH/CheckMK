#!/bin/bash

/usr/lib/check_mk_agent/check_hetzner.sh >/usr/lib/check_mk_agent/check_hetzner_buffer_tmp.txt
mv -f /usr/lib/check_mk_agent/check_hetzner_buffer_tmp.txt /usr/lib/check_mk_agent/check_hetzner_buffer.txt

exit 0