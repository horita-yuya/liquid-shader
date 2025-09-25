# liquid shader

This repository is a demo project showcasing liquid-like and glass-like visual effects built with Apple's Metal shader language (MSL).

# Getting Started

1. Add dependencies
```
.package(url: "https://github.com/horita-yuya/liquid-shader")
```

2. import Liquid
```swift
import SwiftUI
import Liquid

struct ContentView: View {
    var body: some View {
        VStack {
            LiquidRippleView()
            LiquidDropletView()
        }
        .padding()
    }
}
```

# Demo (takes long time for preview)

![Liquid Glass Demo](./docs/demo.gif)

# How it Works

The effect is based on a simple idea: 
- treat each pixel of the background as light.
- By bending (refraction) or bouncing (reflection) that light according to a simulated liquid surface, we can create the illusion of liquid.
