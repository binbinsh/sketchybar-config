# Instructions for sketchybar-config

## General Instructions
- Always query context7 for the most recent docs and best practices.
- All comments, logs and documentations in English.
- Include only brief end-user instructions in the root README.md file.
- Place detailed development documentation in docs/*.md (use lowercase filenames).
- No legacy code, no backward compatibility.

## Performance optimizations
Performance focus: This is a **performance-critical lightweight binary**: should can be configured to have a very small performance footprint. The following highlight some optimizations that can be used to reduce the footprint further.

- Batch together configuration commands where ever possible.
- Set updates=when_shown for items that do not need to run their script if they are not rendered.
- Reduce the update_freq of scripts and aliases and use event-driven scripting when ever possible.
- Do not add aliases to apps that are not always running, otherwise SketchyBar searches for them continuously.
- Use compiled mach_helper programs that directly interface with SketchyBar example for performance sensitive tasks
