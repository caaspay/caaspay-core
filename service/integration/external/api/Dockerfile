FROM python:alpine3.15

workdir /code

# Install curl for healthchecks
RUN apk --update add --no-cache g++ wget curl make

# Setup a nonroot user for security
RUN adduser -D nonroot
USER nonroot

# Upgrade pip
RUN pip install --upgrade pip

# Install dependencies
COPY ./requirements.txt /code/requirements.txt
RUN pip install --user --no-cache-dir --upgrade -r requirements.txt

# Expose the app's port
EXPOSE 8000

workdir /code/app

# Run the FastAPI server
ENTRYPOINT ["python", "-m"] 
#CMD ["uvicorn", "main:app", "--proxy-headers", "--host", "0.0.0.0", "--port", "8000", "--reload"]
