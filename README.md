# liquid shader

This repository is a demo project showcasing liquid-like and glass-like visual effects built with Apple's Metal shader language (MSL).

# Demo

![Liquid Glass Demo](./docs/demo.mov)

# How it Works

The effect is based on a simple idea: 
- treat each pixel of the background as light.
- By bending (refraction) or bouncing (reflection) that light according to a simulated liquid surface, we can create the illusion of liquid.
