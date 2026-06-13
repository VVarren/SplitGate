import os
import sys
import time
from pathlib import Path

from alibabacloud_ecs20140526 import models as ecs_models
from alibabacloud_ecs20140526.client import Client
from alibabacloud_tea_openapi import models as open_api_models
from dotenv import load_dotenv

COMMANDS = {'on', 'off', 'status'}


def _make_client(access_key_id, access_key_secret, region):
    config = open_api_models.Config(
        access_key_id=access_key_id,
        access_key_secret=access_key_secret,
        region_id=region,
    )
    return Client(config)


def _get_status(client, region, instance_id):
    req = ecs_models.DescribeInstanceStatusRequest(
        region_id=region,
        instance_id=[instance_id],
    )
    resp = client.describe_instance_status(req)
    return resp.body.instance_statuses.instance_status[0].status


def _wait_for(client, region, instance_id, target):
    while True:
        if _get_status(client, region, instance_id) == target:
            return
        time.sleep(5)


def _on(client, region, instance_id, eip):
    if _get_status(client, region, instance_id) == 'Running':
        print('Already running.')
        return
    client.start_instance(ecs_models.StartInstanceRequest(instance_id=instance_id))
    print('Starting...', end='', flush=True)
    _wait_for(client, region, instance_id, 'Running')
    print(f' Ready. Connect via {eip}')


def _off(client, region, instance_id):
    if _get_status(client, region, instance_id) == 'Stopped':
        print('Already stopped.')
        return
    client.stop_instance(ecs_models.StopInstanceRequest(
        instance_id=instance_id,
        stopped_mode='StopCharging',
        force_stop=False,
    ))
    print('Stopping...', end='', flush=True)
    _wait_for(client, region, instance_id, 'Stopped')
    print(' Stopped. Compute charges paused.')


def _status(client, region, instance_id):
    print(_get_status(client, region, instance_id))


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]

    if len(argv) != 1 or argv[0] not in COMMANDS:
        print(f'Usage: proxy <{" | ".join(sorted(COMMANDS))}>', file=sys.stderr)
        return 1

    load_dotenv(Path(__file__).parent / '.env')
    access_key_id = os.environ['ALIBABA_ACCESS_KEY_ID']
    access_key_secret = os.environ['ALIBABA_ACCESS_KEY_SECRET']
    instance_id = os.environ['ALIBABA_INSTANCE_ID']
    region = os.environ['ALIBABA_REGION']
    eip = os.environ['PROXY_EIP']

    client = _make_client(access_key_id, access_key_secret, region)

    if argv[0] == 'on':
        _on(client, region, instance_id, eip)
    elif argv[0] == 'off':
        _off(client, region, instance_id)
    elif argv[0] == 'status':
        _status(client, region, instance_id)

    return 0


if __name__ == '__main__':
    sys.exit(main())
