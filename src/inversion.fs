#version 330 core
out vec4 FragColor;

// Input from the vertex shader
in vec2 fragTexCoord; // Texture coordinates (normalized to [0, 1])

uniform sampler2D image; // The input image texture
uniform vec2 circleCenter; // Circle center in pixel coordinates
uniform float circleRadius; // Circle radius in pixel coordinates
uniform vec2 textureSize; // Texture dimensions (width, height)

vec2 invert(vec2 point, vec2 center, float radius) {
    vec2 delta = point - center;
    float distSquared = dot(delta, delta);
    return center + (radius * radius * delta) / distSquared;
}

const float CENTER_RADIUS = 3.2;
const float EDGE_THICKNESS = 0.8;
const vec4 CIRCLE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);

void main() {
    // Convert normalized texture coordinates to pixel coordinates
    vec2 pixelCoords = fragTexCoord * textureSize;

    float dist = distance(pixelCoords, circleCenter);
    // Check if the current pixel is near the edge of the circle
    if(circleRadius - EDGE_THICKNESS < dist && dist < circleRadius + EDGE_THICKNESS) {
        FragColor = CIRCLE_COLOR;
        return;
    }
    // Check if the current pixel is near the center of the circle
    if(dist < CENTER_RADIUS) {
        FragColor = CIRCLE_COLOR;
        return;
    }

    // Invert the current pixel coordinate
    vec2 invertedCoords = invert(pixelCoords, circleCenter, circleRadius);

    // Convert back to normalized texture coordinates
    vec2 texCoords = invertedCoords / textureSize;

    // Discard fragments that map outside the texture
    if (texCoords.x < 0.0 || texCoords.x > 1.0 || texCoords.y < 0.0 || texCoords.y > 1.0) {
        discard;
    }

    // Sample the texture at the inverted coordinates
    FragColor = texture(image, texCoords);
}