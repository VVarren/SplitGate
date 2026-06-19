import time

from alibabacloud_ecs20140526 import models as ecs_models
from alibabacloud_ecs20140526.client import Client
from alibabacloud_tea_openapi import models as open_api_models


def make_client(settings):
    config = open_api_models.Config(
        access_key_id=settings["ALIBABA_ACCESS_KEY_ID"],
        access_key_secret=settings["ALIBABA_ACCESS_KEY_SECRET"],
        region_id=settings["ALIBABA_REGION"],
    )
    return Client(config)


def get_status(client, region, instance_id):
    req = ecs_models.DescribeInstanceStatusRequest(region_id=region, instance_id=[instance_id])
    resp = client.describe_instance_status(req)
    return resp.body.instance_statuses.instance_status[0].status


def wait_for(client, region, instance_id, target, max_wait=120):
    for _ in range(max_wait // 5):
        if get_status(client, region, instance_id) == target:
            return
        time.sleep(5)
    raise TimeoutError(f"Instance did not reach {target!r} within {max_wait}s")


def cloud_on(settings, client=None):
    client = client or make_client(settings)
    region, iid = settings["ALIBABA_REGION"], settings["ALIBABA_INSTANCE_ID"]
    if get_status(client, region, iid) == "Running":
        print("Already running.")
        return
    client.start_instance(ecs_models.StartInstanceRequest(instance_id=iid))
    print("Starting...", end="", flush=True)
    wait_for(client, region, iid, "Running")
    print(f" Ready. Connect via {settings['PROXY_EIP']}")


def cloud_off(settings, client=None):
    client = client or make_client(settings)
    region, iid = settings["ALIBABA_REGION"], settings["ALIBABA_INSTANCE_ID"]
    if get_status(client, region, iid) == "Stopped":
        print("Already stopped.")
        return
    client.stop_instance(ecs_models.StopInstanceRequest(
        instance_id=iid, stopped_mode="StopCharging", force_stop=False))
    print("Stopping...", end="", flush=True)
    wait_for(client, region, iid, "Stopped")
    print(" Stopped. Compute charges paused.")


def cloud_status(settings, client=None):
    client = client or make_client(settings)
    print(get_status(client, settings["ALIBABA_REGION"], settings["ALIBABA_INSTANCE_ID"]))
