import SwiftUI
import Liquid

@main
struct SampleApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                ZStack(alignment: .bottomTrailing) {
                    LiquidRippleView()
                    Text("Liquid-like")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.all, 8)
                }
                ZStack(alignment: .bottomTrailing) {
                    LiquidDropletView()
                    Text("Glass-like")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.all, 8)
                }
            }
        }
    }
}
