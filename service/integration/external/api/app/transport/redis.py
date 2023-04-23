import asyncio
import redis.asyncio as redis
#import redis
import uuid
from loguru import logger
import json

from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

RPC_PREFIX = 'myriad.service'
RPC_SUFFIX = 'rpc'

class TransportMessage(BaseModel):
    rpc: str
    who: str
    message_id: int
    transport_id: str = None
    deadline: int = int(datetime.now().timestamp()) + 30
    args: str
    response: dict = None
    stash: dict = None
    trace: dict = None

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
                message = TransportMessage(**json.loads(raw_message["data"]))
                logger.info(f"(PubSub) Message Received: {message}")
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
        args["deadline"] = int(datetime.now().timestamp()) + timemout
        request = TransportMessage(**{"rpc": method, "who": self.channel, "message_id": message_id, "args": json.dumps(args)})

        stream_name = stream_name_from_service(service, method)

        response_future = loop.create_future()
        self.pending[message_id] = response_future
        logger.info(request.dict(exclude_none=True))
        await self.redis.xadd(stream_name, request.dict(exclude_none=True))
        await self.redis.publish(self.channel, request.json());
        try:
            response = await asyncio.wait_for(response_future, timeout=timemout)
            self.pending.pop(message_id, None)
            return response
        except asyncio.TimeoutError:
            request.response = {"error": 1, "reason": "timeout", "timeout":timeout}
            self.pending.pop(message_id, None)
            return request
        #return await response_future

class TransportRedis():
    def __init__(self, node_name: str, is_cluster: bool):
        self.is_cluster = is_cluster
        if is_cluster:
            self.redis = redis.cluster.RedisCluster(host=node_name, port=6379, decode_responses=True)
        else:
            self.redis = redis.client.Redis(host=node_name, port=6379, decode_responses=True)
        self.whoami = str(uuid.uuid1())
        self.client_rpc = TransportClientRPC(redis=self.redis, channel=self.whoami)

    async def get_test_key(self):
        return await self.redis.get('test_key')

    def test(self):
        return stream_name_from_service('test_service', 'test_method')

    async def subscribe(self):
        #await self.redis.publish(self.whoami, "Hello")
        #await self.redis.publish(self.whoami, "World")
        #await self.redis.publish(self.whoami, "EXIT")
        return 1

 
