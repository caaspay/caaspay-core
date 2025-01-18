from passlib.context import CryptContext
#from fastapi.security import HTTPBasicCredentials
#from fastapi.security import HTTPBasic
from fastapi import Depends
from fastapi.security import OAuth2PasswordBearer
#from secrets import compare_digest
from transport.redis import TransportClientRPC
from loguru import logger
#from models.data.sqlalchemy_models import Login
crypt_context = CryptContext(schemes=["sha256_crypt", 
                    "md5_crypt"])
#http_basic = HTTPBasic()
from pydantic import BaseModel, SecretStr, Field, validator
from typing import List, Optional

oauth2_scheme = OAuth2PasswordBearer(tokenUrl = "login/token")

class User(BaseModel):
    username: str
    email: str = Field(None)
    password: SecretStr = Field(None, exclude=True)
    passphrase: str = Field(None)
    approved: bool = Field(None)
    client_id: str = Field(None)
    client_secret: str = Field(None)
    scopes: List[str] = Field([None])
    grant_type: str = Field(None)

    @validator('client_id', pre=True, always=True)
    def set_client_id(cls, v, values):
        return 'root' if v is None else v
    @validator('passphrase', pre=True, always=True)
    def set_passphrase(cls, v, values):
        return crypt_context.hash(values['password'].get_secret_value())
    
class Authentication():
    def __init__(self, transport_rpc: TransportClientRPC):
        self.rpc = transport_rpc
    async def login(self, user: User):
        logger.info(f"UUUSER: {user}")
        #check = await self.rpc.call('control.authentication.login', 'login', {"username": user.username, "password": str(user.password)})
        check = await self.rpc.call('control.authentication.login', 'login', user.dict())
        self.user = user
        logger.info(f"CHECK: {check}")
    async def get_current_user(self, token: str = Depends(oauth2_scheme)):
        logger.info(f"AUTH get_current_user: {token}")
        #user = await self.rpc.call('control.authentication.login', 'current_user', token)
        user = await self.rpc.call('control.authentication.login', 'login', token)
        logger.info(f"CHECK: {self.user}")
        return self.user


#def verify_password(plain_password, hashed_password):
#    return crypt_context.verify(plain_password, 
#        hashed_password)
#def authenticate(credentials: HTTPBasicCredentials, 
#         user:User):
#    try:
#        is_username = compare_digest(credentials.username,
#             user.username)
#        is_password = compare_digest(credentials.password, 
#             user.username)
#        verified_password = verify_password(credentials.password, user.passphrase)
#        return (verified_password and is_username and is_password)
#    except Exception as e:
#        return False

async def get_current_user(token: str = Depends(oauth2_scheme), transport_rpc: TransportClientRPC=None):
    logger.info(f"get_current_user: {token}")
    #user = await self.rpc.call('control.authentication.login', 'current_user', token)
    user = await transport_rpc.call('control.authentication.login', 'login', token)
    #logger.info(f"CHECK: {self.user}")
    #return self.user
    return User(**{username: "test", password: "fffff"})

def get_login(username):
	return User('test', 'pass')

