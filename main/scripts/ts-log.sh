#!/bin/bash
# 给标准输入的每一行加上 wall-clock 时间戳
# 用法：some_command 2>&1 | ./ts-log.sh > output.log
exec awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0 }'
