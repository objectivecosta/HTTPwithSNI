//
//  ContentView.swift
//  HTTPwithSNI
//
//  Created by Rafael Costa on 2024-03-29.
//

import SwiftUI

struct ContentView: View {
    
    var request: RequestExecutor = RequestExecutor(
        parameters: RequestParameters()) { data, error in
            print("Error:", error)
            print("Response:", data != nil ? String(data: data!, encoding: .utf8) : "")
        }
    
    var body: some View {
        VStack {
            Button {
                request.setup()
            } label: {
                Text(verbatim: "Sent request to custom IP address")
            }

        }
        .padding()
    }
}

#Preview {
    ContentView()
}
