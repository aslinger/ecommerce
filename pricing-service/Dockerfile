# Using a lightweight Python base image
FROM python:3.11-slim-bookworm

# Set environment variable for Python to flush output immediately (good for containers)
ENV PYTHONUNBUFFERED 1

# Set the application directory
WORKDIR /app

# Copy the requirements file and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY consumer.py .

# Run the SQS consumer script continuously
CMD [\"python\", \"consumer.py\"]
