from typing import Optional

from fastapi import FastAPI, Depends, HTTPException
import asyncio
from loguru import logger

#from util.auth_session import secret_key
from starlette.middleware import Middleware
from starlette.middleware.sessions import SessionMiddleware
from starlette.middleware.cors import CORSMiddleware

from jose import JWTError, jwt
from fastapi.security import OAuth2PasswordBearer
from fastapi.security import OAuth2PasswordRequestForm
from transport.redis import TransportRedis, TransportClientRPC
from security.secure import Authentication, get_current_user, User, get_login


from pydantic import BaseSettings

class APISettings(BaseSettings):
    TRANSPORT_REDIS_CLUSTER:bool = False
    TRANSPORT_REDIS_NODE:str = 'redis'

settings = APISettings()
logger.info(f"ddd {settings.TRANSPORT_REDIS_CLUSTER}")
transport = TransportRedis(settings.TRANSPORT_REDIS_NODE, settings.TRANSPORT_REDIS_CLUSTER)

def get_rpc():
    return transport.client_rpc


origins = [
    "https://192.168.10.2",
    "http://192.168.10.2",
    "https://localhost:8080",
    "http://localhost:8080"
]

oauth2_scheme = OAuth2PasswordBearer(tokenUrl = "login/token")

app = FastAPI(middleware=[
           Middleware(SessionMiddleware, secret_key=
            '7UzGQS7woBazLUtVQJG39ywOP7J7lkPkB0UmDhMgBR8=',
               session_cookie="session_vars")
            ])
app.add_middleware(CORSMiddleware, max_age=3600,
     allow_origins=origins, allow_credentials=True,
     allow_methods= ["POST", "GET", "DELETE",
       "PATCH", "PUT"], allow_headers=[
            "Access-Control-Allow-Origin",
            "Access-Control-Allow-Credentials",
            "Access-Control-Allow-Headers",
            "Access-Control-Max-Age"])


@app.on_event('startup')
async def app_startup():
    asyncio.create_task(transport.client_rpc.setup())


@app.get("/")
async def read_root():
    await asyncio.sleep(2)
    return {"Hello": "World2"}

@app.get("/health")
def read_root():
    return "OK"

@app.post("/login/token")
async def login(form_data: OAuth2PasswordRequestForm = Depends()): # add DB session
    username = form_data.username
    password = form_data.password
    authentication = Authentication(transport.client_rpc)

    login_user = User(**{"username": form_data.username, "password": form_data.password, "client_id": form_data.client_id, "client_secret": form_data.client_secret, "scopes": form_data.scopes,  "grant_type": form_data.grant_type })
    login_trial = await authentication.login(login_user)
    #account = get_login('test')
    #logger.add("info.log",format="Log: [{extra[log_id]}: 
    #   {time} - {level} - {message} ", level="INFO", 
    #   enqueue = True)
    test_key = await transport.get_test_key()
    await transport.subscribe()
    result = await transport.client_rpc.call('control.authentication.login', 'login', {"arg1": 'arg1v', "arg2": 'arg2v'})
    #logger.info("LOGIN: username: " + account.username + " ( " + transport.test() + " ) | password: " + account.password + " | account: " + account.account)
    logger.info("RESULT: " + result.json())
    return result

#@app.get("/checkh")
#def check(current_user: User = Depends(get_current_user),):
#    return current_user
