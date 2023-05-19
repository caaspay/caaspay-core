from passlib.context import CryptContext
from fastapi.security import HTTPBasicCredentials
from fastapi.security import HTTPBasic
from secrets import compare_digest
from transport.redis import TransportClientRPC
#from models.data.sqlalchemy_models import Login
crypt_context = CryptContext(schemes=["sha256_crypt", 
                    "md5_crypt"])
http_basic = HTTPBasic()
from pydantic import BaseModel, SecretStr, Field
from typing import List, Optional

class UserAccount(BaseModel):
    type_name: str
    approved: bool = False
    info: dict = None
class User(BaseModel):
    username: str
    email: str = Field(None)
    password: SecretStr = Field(None)
    passphrase: str = Field(None)
    approved: bool = Field(None)
    accounts: List[UserAccount] = Field(None)
    
class Authentication():
    def __init__(self, transport_rpc: TransportClientRPC):
        self.rpc = transport_rpc
    async def login(self, user: User):
        check = await self.rpc.call('control.authentication.login', 'login', {"username": user.username, "password": str(user.password)})
        logger.info(f"CHECK: {check}")


def verify_password(plain_password, hashed_password):
    return crypt_context.verify(plain_password, 
        hashed_password)
def authenticate(credentials: HTTPBasicCredentials, 
         user:User):
    try:
        is_username = compare_digest(credentials.username,
             user.username)
        is_password = compare_digest(credentials.password, 
             user.username)
        verified_password = verify_password(credentials.password, user.passphrase)
        return (verified_password and is_username and is_password)
    except Exception as e:
        return False

def get_current_user():
    return True

def get_login(username):
	return User('test', 'pass')

