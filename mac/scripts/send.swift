#!/usr/bin/env swift
// Sends a raw request to the running Connect Head app, for probing the protocol.
// Usage: scripts/send.swift <message type> <payload bytes…>   e.g.  scripts/send.swift 0c 66 17
// Watch replies with: /usr/bin/log stream --predicate 'subsystem == "local.sonycontrol"' --level debug
import Foundation

let bytes = CommandLine.arguments.dropFirst().joined(separator: " ")
DistributedNotificationCenter.default().postNotificationName(
    .init("local.sonycontrol.send"), object: bytes, deliverImmediately: true)
