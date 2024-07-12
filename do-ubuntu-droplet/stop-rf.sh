#!/bin/bash

docker compose down && docker image remove ui && docker image remove viewer && docker image remove control-panel && docker image remove gateway