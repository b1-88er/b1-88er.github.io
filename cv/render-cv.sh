#!/bin/bash
set -x
# npm install -g resume-cli
resume export --theme stackoverflow --format html cv.html
mv cv.html ../static/
