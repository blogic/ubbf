'use strict';

// Auto-generated schema definitions for IndividualPacketResult domain
// Generated from TR-181 specifications

// Schema for IndividualPacketResult.{i}.
export const IndividualPacketResult = {
    path: "IndividualPacketResult.{i}.",
    schema: {
        "PacketSuccess": dm_type.BOOL,
        "PacketSendTime": dm_type.DATETIME,
        "PacketReceiveTime": dm_type.DATETIME,
        "TestGenSN": dm_type.UINT,
        "TestRespSN": dm_type.UINT,
        "TestRespRcvTimeStamp": dm_type.UINT,
        "TestRespReplyTimeStamp": dm_type.UINT,
        "TestRespReplyFailureCount": dm_type.UINT
    },
    defaults: {
        "TestGenSN": "0",
        "TestRespSN": "0",
        "TestRespRcvTimeStamp": "0",
        "TestRespReplyTimeStamp": "0",
        "TestRespReplyFailureCount": "0"
    }
};
