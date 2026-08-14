# CustomSkinAPI
#### Revision 2
## API Significance

- Effectively reduces network requests
- Effectively ensures the validity of skin cache
- Easier to change skin models
- Makes the skin loading process easier to understand

## API Application

You can implement skin loading based on this API in any project.

CustomSkinLoader has supported CustomSkinAPI R1 since version 13.1.
CustomSkinLoader has supported CustomSkinAPI R2 since version 14.5.

## API Definition

### API Request Specification

GET request without any parameters.

### API Response Specification

GZIP and redirection can be used.

Respond to `If-Modified-Since` whenever possible.
Return correct and valid `Content-Length` and `Last-Modified` headers whenever possible; other HTTP headers are optional.

Can respond with `Cache-Control` or `Expires` headers (the former takes precedence). CustomSkinLoader will use these to determine content validity.

### Root Address

The root address defines the URLs that can respond to CustomSkinAPI.

The root address can be a domain, such as `http://localhost/`, or include a port, such as `http://localhost:8080/`. It can also include subfolders, such as `http://localhost/csl/`.

**Please note** that the root address must end with `/`.

In the following content, the root address will be represented by `{ROOT}`.

### User Information

Please try to generate easy-to-read, formatted JSON; compressed JSON is also acceptable.

#### JSON Format
```
{
    "username": "{string, player name with correct case}",
    "textures": {textures dictionary}
}
```
The above is the usual JSON format. The following shorthand can also be used, in which case the skin will use the `default` model:
```
{
    "username": "{string, player name with correct case}",
    "skin": "{unique resource identifier for skin}",
    "cape": "{unique resource identifier for cape}",
    "elytra": "{unique resource identifier for elytra}"
}
```

If items are repeated, the ones in `textures` take precedence.
All items are optional. If they don't exist, they can be omitted, left empty, or set to `null`.
For example, `"cape": ""` or `"cape": null`.

#### Textures Dictionary
```
{
    "{first model}": "{unique resource identifier}",
    "{second model}": "{unique resource identifier}"
}
```
##### Available Models
- `(,1.7.10]` `default` `cape`
- `[1.8,1.8.9]` `default` `slim` `cape`
- `[1.9,)` `default` `slim` `cape` `elytra`
##### Skin Models
The order of skins in the textures dictionary should match the user's preference.
In clients that support dual `slim`/`default` models, the skin and model to load will be determined by the order in the textures dictionary.
In clients that only support the `default` model, the texture corresponding to the `default` model will be loaded directly.
In this case, if only the `slim` model is specified, the `default` model will be used with the `slim` skin, **which will cause arm rendering errors**.

#### JSON Examples
Complete user info JSON:
```
{
    "username": "test",
    "textures": {
        "default": "6dc40bc8af6a48861b914d36dc1437446a977b644ab7f9c4942f79173d315b30",
        "slim": "b2c4ef891f01c5a8e2dc8a832bc3a89c32b59ee3dadc1c4de6e357f997d2dbaf",
        "cape": "aed8c3fc67aae4906b72fa74c27e15866c89752f0838f6b2a1c44bb4d59cec1e",
        "elytra": "b6a865cc67aae4906b72fa74c27e15866c895f270838f6b2a1c44bb4d5954ca8"
    }
}
```
Shorthand:
```
{
    "username": "test",
    "skin": "b2c4ef891f01c5a8e2dc8a832bc3a89c32b59ee3dadc1c4de6e357f997d2dbaf",
    "cape": "aed8c3fc67aae4906b72fa74c27e15866c89752f0838f6b2a1c44bb4d59cec1e",
    "elytra": "b6a865cc67aae4906b72fa74c27e15866c895f270838f6b2a1c44bb4d5954ca8"
}
```
## API Interfaces
### Get User Info
Request URL: `{ROOT}/{USERNAME}.json`

Where `{USERNAME}` is case-insensitive.

Response:
- 200 Player found, returns user info
- 404 Player not found

### Get Resource File
Request URL: `{ROOT}/textures/{unique resource identifier}`

Response:
- 200 Resource found and returned
- 404 Resource not found

`{unique resource identifier}` can be customized as any unique string; SHA-256 is recommended.
