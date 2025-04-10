//
//  PacketModel.swift
//  mDNSShark
//
//  Created by user on 4/10/25.
//


//
//  PacketModel.swift
//  mDNSShark
//
//  Created by user on 3/19/25.
//

import Foundation

struct PacketModel: Identifiable {
    let id = UUID()
    
    let frameNumber: Int
    let time: String
    let source: String
    let destination: String
    let protocolName: String
    let length: Int
    let info: String
    let hexDump: String
}
