#!/usr/bin/env python3

# Version: 1.0.0

import json
import os
import pprint
import re
import requests
import sys
import time

###
### all metric names
###
# caddy_config_last_reload_successful
# caddy_http_request_duration_seconds_bucket
# caddy_http_request_duration_seconds_count
# caddy_http_request_duration_seconds_sum
# caddy_http_request_errors_total
# caddy_http_requests_in_flight
# caddy_http_request_size_bytes_bucket
# caddy_http_request_size_bytes_count
# caddy_http_request_size_bytes_sum
# caddy_http_requests_total
# caddy_http_response_duration_seconds_bucket
# caddy_http_response_duration_seconds_count
# caddy_http_response_duration_seconds_sum
# caddy_http_response_size_bytes_bucket
# caddy_http_response_size_bytes_count
# caddy_http_response_size_bytes_sum
# caddy_reverse_proxy_upstreams_healthy
# go_build_info
# go_gc_duration_seconds
# go_gc_duration_seconds_count
# go_gc_duration_seconds_sum
# go_goroutines
# go_info
# go_memstats_heap_objects
# go_memstats_lookups_total
# go_memstats_mcache_inuse_bytes
# go_memstats_mcache_sys_bytes
# go_threads
# process_cpu_seconds_total
# process_open_fds
# promhttp_metric_handler_requests_in_flight
# promhttp_metric_handler_requests_total

def dbg(msg):
    global debug
    if debug:
        print(f"DEBUG: {msg}")

def dbg_pprint(msg, elt):
    global debug
    if debug:
        print(f"DEBUG: {msg}")
        pprint.pprint(elt)

def env_to_bool(variable):
    value = os.getenv(variable)
    return False if not value else value.lower() in [ "1", "yes", "true" ]

def load_state():
    global state

    try:
        with open(state_file, "r") as f:
            state = json.loads(f.read())
    except Exception as _:
        state = {}

def save_state():
    global state, now

    state["last_run_at"] = now

    with open(state_file, "w") as f:
        f.write(json.dumps(state, indent=2))

def is_empty(val):
    if val is None:
        return True

    if (val is list) or (val is dict) or (val is bool):
        return not val

    if val is str:
        return val == ""

    return False

def fetch_metrics():
    global conf

    url = conf.get("metrics_url", "http://localhost:2019/metrics")

    try:
        res = requests.get(url, timeout=4)

        if res.status_code != 200:
            dbg(f"GET {url} failed with code {res.status_code}")
            sys.exit(0)

        return res.content.decode()

    except Exception as _:
        dbg(f"exception GET {url}")
        sys.exit(0)

def parse_metrics(content):
    re_line = re.compile(r'^([a-z0-9_]+)(\{(.*)\})? +([0-9.e+]+) *$')
    re_strip_quotes = re.compile(r'^"|"$')
    metrics = []

    for line in content.split("\n"):
        if (len(line) == 0) or (line[0] == '#'):
            continue

        # caddy_http_request_duration_seconds_bucket{code="200",handler="subroute",method="GET",server="srv1",le="+Inf"} 119853

        matches = re_line.match(line)
        if not matches:
            continue

        name, labels_str, value = matches[1], matches[3], matches[4]

        if is_empty(name) or is_empty(value):
            continue

        labels = {}
        if not is_empty(labels_str):
            for l_kv_pair in labels_str.split(","):
                l_key, l_value = l_kv_pair.split("=")
                labels[l_key] = re.sub(re_strip_quotes, '', l_value)

        value = re.sub(re_strip_quotes, '', value)
        value = float(value) if '.' in value else int(value)

        # print(name)
        # print(line)
        # pprint.pprint(labels)

        # print(len(line))

        metrics.append({
            "name": name,
            "labels": labels,
            "value": value,
        })

    return metrics

def scan_metrics(metrics):
    global status

    to_sum = [
        # "caddy_http_response_size_bytes_bucket",
        # "caddy_http_request_duration_seconds_bucket",
        "caddy_http_response_size_bytes_sum",
        "caddy_http_response_duration_seconds_sum",
        "caddy_http_requests_in_flight",
        "caddy_http_requests_total",
        "caddy_http_request_errors_total",
        "process_cpu_seconds_total",
    ]

    values = {}
    details = []

    for metric in metrics:
        name, value, _ = metric["name"], metric["value"], metric["labels"]

        if name in to_sum:
            s_name = re.sub(r'^caddy_http_', '', name)

            if s_name not in values:
                values[s_name] = 0

            if name == "caddy_http_response_size_bytes_sum":
                dbg_pprint(f"scan_metrics: caddy_http_response_size_bytes_sum value {value} labels", metric["labels"])

            values[s_name] += value

        elif name == "caddy_config_last_reload_successful":
            if value == 1:
                details.append("last reload successful")

            else:
                details.append("last reload failed")
                status = 2

    dbg_pprint("scan_metrics: values", values)

    return values, details

def evaluate_metrics(values, details):
    global state, now, conf

    # pprint.pprint(metrics)

    # pprint.pprint(values)

    if is_empty(details):
        details.append("metrics retrieved")

    prev_values = state.get("values", {})

    if is_empty(values.get("requests_total")) or is_empty(prev_values.get("requests_total")):
        prev_values = None

    elif values["requests_total"] < prev_values["requests_total"]:
        prev_values = None

    time_diff = now - state["last_run_at"] if "last_run_at" in state else -1

    svc_metrics = []

    num_requests = values.get("requests_total")

    if (time_diff > 0) and (prev_values is not None):
        prev_num_requests = prev_values.get("requests_total")
        requests_diff = None

        if (num_requests is not None) and (prev_num_requests is not None):
            rate = (num_requests - prev_num_requests) / time_diff
            if rate >= 0:
                svc_metrics.append(f"requests_per_second={rate}")

            if num_requests != prev_num_requests:
                requests_diff = num_requests - prev_num_requests

        errors, prev_errors = values.get("request_errors_total"), prev_values.get("request_errors_total")
        if (errors is not None) and (prev_errors is not None):
            rate = (errors - prev_errors) / time_diff
            if rate >= 0:
                svc_metrics.append(f"error_rate={rate}")

        duration, prev_duration = values.get("response_duration_seconds_sum"), prev_values.get("response_duration_seconds_sum")
        if (duration is not None) and (prev_duration is not None) and (requests_diff is not None):
            duration_per_request = (duration - prev_duration) / requests_diff
            if duration_per_request >= 0:
                svc_metrics.append(f"average_request_time={duration_per_request}")

        size, prev_size = values.get("response_size_bytes_sum"), prev_values.get("response_size_bytes_sum")
        if (size is not None) and (prev_size is not None):
            rate = (size - prev_size) / time_diff
            if rate >= 0:
                svc_metrics.append(f"data_transfer_rate={rate}")

            if requests_diff is not None:
                rate = (size - prev_size) / requests_diff
                if rate >= 0:
                    svc_metrics.append(f"request_transfer_rate={rate}")

    in_flight = values.get("requests_in_flight")
    if in_flight is not None:
        svc_metrics.append(f"active={in_flight}")

    if num_requests is not None:
        svc_metrics.append(f"accepted_connections={num_requests}")

    svc_metrics_str = "|".join(svc_metrics) if svc_metrics else  "-"

    service_name = conf.get("service_name", "Caddy status")

    print(f"{status} '{service_name}' {svc_metrics_str} {'; '.join(details)}")

    state["values"] = values

def setup():
    global debug, status, state_file, state, now, conf

    var_dir = os.getenv("MK_VARDIR")
    etc_dir = os.getenv("MK_CONFDIR")
    if is_empty(etc_dir):
        etc_dir = "/etc/check_mk"

    debug = env_to_bool("DEBUG")
    status = 0
    state = {}
    now = time.time()

    state_file = "linet_caddy_metrics.json"
    if not is_empty(var_dir):
        state_file = f"{var_dir}/persisted/{state_file}"

    conf_file = f"{etc_dir}/linet_caddy_metrics.json"
    conf = {}

    try:
        with open(conf_file, "r") as f:
            conf = json.loads(f.read())
    except Exception as _:
        conf = {}

def main():
    setup()

    load_state()

    values, details = scan_metrics(parse_metrics(fetch_metrics()))
    evaluate_metrics(values, details)

    save_state()

main()
