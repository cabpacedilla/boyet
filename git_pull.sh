#!/usr/bin/bash

echo "changing to frontend project directory..."
cd ~/local_env/frontend || { echo "Directory not found"; exit 1; }
git checkout -f local
if [ -z "$1" ]; then
	echo "Please provide the PR branch"
else
	git pull origin "$1"	
fi

git checkout -f "$1"
if [ $? -eq 0 ]; then
	echo "Checkout to $1 in ~/localenv/frontend was successful"
fi

echo "changing to backend directory..."
cd ~/local_env/backend || { echo "Directory not found"; exit 1; }
git checkout -f local
if [ -z "$1" ]; then
	echo "Please provide the PR branch"
else
	git pull origin "$1"
fi

git checkout -f "$1"
if [ $? -eq 0 ]; then
	echo "Checkout to $1 in ~/localenv/backend was successful"
fi

