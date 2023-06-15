//
//  ContentView.swift
//  RoStrap
//
//  Created by iivusly on 5/10/23.
//

import SwiftUI

struct ContentView: View {
	@Binding var stateMessage: String
	@Binding var stateValue: Double?
	
    var body: some View {
        VStack {
			VStack {
				Image(systemName: "gamecontroller")
					.resizable()
					.scaledToFit()
					.rotationEffect(Angle.degrees(20))
					.frame(maxWidth: 100, maxHeight: 100)
				Text("Ro-Strap").font(.title)
			}.frame(maxWidth: .infinity, maxHeight: .infinity)
			HStack {
				ProgressView(value: stateValue, label: {
					Text(stateMessage)
				}).frame(maxWidth: .infinity)
				Spacer()
			}
        }
		.padding()
		.background(.ultraThinMaterial)
		.frame(width: 500, height: 320, alignment: .center)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
		ContentView(stateMessage: .constant("Loading..."), stateValue: .constant(nil))
    }
}
