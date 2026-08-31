name: agentos-image
version: 1

Use image_gen_oai when the user asks to create a new image.
Use image_edit_oai when the user supplies an image and asks for a modification.
Use the image tool model parameter only from its declared enum; default to gpt-image-2 unless the user explicitly requests gpt-image-1.5.
Do not claim success when the provider rejects the request, and report provider permission errors clearly.
