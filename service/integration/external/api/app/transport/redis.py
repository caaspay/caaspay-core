import asyncio
import redis.asyncio as redis
#import redis
import uuid
from loguru import logger
import json

from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
from fastapi import HTTPException

RPC_PREFIX = 'myriad.service'
RPC_SUFFIX = 'rpc'
CHANNEL_PREFIX = 'myriad'

class TransportMessage(BaseModel):
    rpc: str
    who: str
    message_id: int
    transport_id: str = None
    deadline: int
    args_dict: dict = None
    args: str = None
    response: dict = None
    stash: dict = None
    trace: dict = None

    def __init__(self, **kwargs):
        if 'args_dict' in kwargs and 'args' not in kwargs:
            kwargs.setdefault('args', json.dumps(kwargs.get('args_dict',{})))
        elif 'args_dict' not in kwargs and 'args' in kwargs:
            kwargs.setdefault('args_dict', json.loads(kwargs.get('args',{})))
        else:
            logger.warning(f"Unmatching args in TransportMessage {kwargs}")
            raise HTTPException(status_code=500, detail="Internal Error - Malformed TransportMessage unmatching response")
        super().__init__(**kwargs)

    def as_message(self):
        return {"rpc": self.rpc, "who": self.who, "message_id": self.message_id, "deadline": self.deadline}

def stream_name_from_service(service_name, method_name):
    return RPC_PREFIX + '.' + service_name + "." + RPC_SUFFIX + '/' + method_name 

class TransportClientRPC():
    def __init__(self, redis, channel):
        self.redis = redis
        self.channel = channel
        self.pending = {}
        self.current_id = 0

    def next_id(self):
        self.current_id = self.current_id + 1
        return self.current_id

    async def pubsub_callback(self, pubsub: redis.client.PubSub):
        while True:
            raw_message = await pubsub.get_message(ignore_subscribe_messages=True)
            if raw_message is not None:
                logger.info(f"(PubSub) Message Received: {raw_message}")
                try:
                    raw_data = json.loads(raw_message["data"])
                    raw_data["response"] = json.loads(raw_data["response"])
                    raw_data["stash"] = json.loads(raw_data["stash"])
                    raw_data["trace"] = json.loads(raw_data["trace"])
                    message = TransportMessage(**raw_data)
                except Exception:
                    logger.warning(f"(PubSub) Message Malformed {raw_message}")
                    raise HTTPException(status_code=500, detail="Internal Error - Malformed TransportMessage format")

                # solve pending future
                if message.message_id in self.pending:
                    self.pending[message.message_id].set_result(message)

    async def setup(self):
        async with self.redis.pubsub() as pubsub:
            await pubsub.subscribe(self.channel)
            logger.info(f"Subscribed to channel: {self.channel}")
            await self.pubsub_callback(pubsub)
            # this to make FastAPI add it as background task instead
            #future = asyncio.create_task(reader(pubsub))
            #await future

    async def call(self, service: str, method: str, args: dict):
        loop = asyncio.get_running_loop()
        # prepare request message arguments
        message_id = self.next_id()
        timemout = args.pop('timeout', None) or 30
        deadline = int(datetime.now().timestamp()) + timemout
        request = TransportMessage(**{"rpc": method, "who": self.channel, "message_id": message_id, "args_dict": args, "deadline": deadline})

        stream_name = stream_name_from_service(service, method)

        response_future = loop.create_future()
        self.pending[message_id] = response_future
        logger.info(request.dict(exclude={'args_dict'},exclude_none=True))
        await self.redis.xadd(stream_name, request.dict(exclude={'args_dict'},exclude_none=True))
        # if there is no service configured to reply
        # you can self reply like this
        # await self.redis.publish(self.channel, request.json());
        try:
            response = await asyncio.wait_for(response_future, timeout=timemout)
            self.pending.pop(message_id, None)
            return response
        except asyncio.TimeoutError:
            logger.warning(f"request timeout {request}")
            self.pending.pop(message_id, None)
            raise HTTPException(status_code=500, detail="Internal Error - Transport timemout")

class TransportRedis():
    def __init__(self, node_name: str, is_cluster: bool):
        self.is_cluster = is_cluster
        if is_cluster:
            self.redis = redis.cluster.RedisCluster(host=node_name, port=6379, decode_responses=True)
        else:
            self.redis = redis.client.Redis(host=node_name, port=6379, decode_responses=True)
        self.whoami = str(uuid.uuid1())
        self.client_rpc = TransportClientRPC(redis=self.redis, channel= '.'.join([CHANNEL_PREFIX, self.whoami]))

    async def get_test_key(self):
        return await self.redis.get('test_key')

    def test(self):
        return stream_name_from_service('control.authentication.login', 'test_rpc')

    async def subscribe(self):
        #await self.redis.publish(self.whoami, "Hello")
        #await self.redis.publish(self.whoami, "World")
        #await self.redis.publish(self.whoami, "EXIT")
        return 1

 
