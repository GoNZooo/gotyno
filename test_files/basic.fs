type Recruiter =
    {
        name: string
    }

    static member Decoder: Decoder<Recruiter> =
        Decode.object (fun get ->
            {
                name = get.Required.Field "name" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "name", Encode.string value.name
            ]

type Maybe<'t> =
    | Nothing
    | Just of 't

    static member NothingDecoder: Decoder<Maybe<'t>> =
        Decode.succeed Nothing

    static member JustDecoder decodeT: Decoder<Maybe<'t>> =
        Decode.object (fun get -> Just(get.Required.Field "data" decodeT))

    static member Decoder decodeT: Decoder<Maybe<'t>> =
        GotynoCoders.decodeWithTypeTag
            "type"
            [|
                "Nothing", Maybe.NothingDecoder
                "Just", Maybe.JustDecoder decodeT
            |]

    static member Encoder encodeT =
        function
        | Nothing ->
            Encode.object [ "type", Encode.string "Nothing" ]

        | Just payload ->
            Encode.object [ "type", Encode.string "Just"
                            "data", encodeT payload ]

type Person =
    {
        name: string
        age: uint8
        efficiency: float32
        on_vacation: bool
        hobbies: list<string>
        last_fifteen_comments: list<string>
        recruiter: Recruiter
        spouse: Maybe<Person>
    }

    static member Decoder: Decoder<Person> =
        Decode.object (fun get ->
            {
                name = get.Required.Field "name" Decode.string
                age = get.Required.Field "age" Decode.byte
                efficiency = get.Required.Field "efficiency" Decode.float32
                on_vacation = get.Required.Field "on_vacation" Decode.bool
                hobbies = get.Required.Field "hobbies" (Decode.list Decode.string)
                last_fifteen_comments = get.Required.Field "last_fifteen_comments" (Decode.list Decode.string)
                recruiter = get.Required.Field "recruiter" Recruiter.Decoder
                spouse = get.Required.Field "spouse" (Maybe.Decoder Person.Decoder)
            }
        )

    static member Encoder value =
        Encode.object
            [
                "name", Encode.string value.name
                "age", Encode.byte value.age
                "efficiency", Encode.float32 value.efficiency
                "on_vacation", Encode.bool value.on_vacation
                "hobbies", GotynoCoders.encodeList Encode.string value.hobbies
                "last_fifteen_comments", GotynoCoders.encodeList Encode.string value.last_fifteen_comments
                "recruiter", Recruiter.Encoder value.recruiter
                "spouse", (Maybe.Encoder Person.Encoder) value.spouse
            ]

type LogInData =
    {
        username: string
        password: string
    }

    static member Decoder: Decoder<LogInData> =
        Decode.object (fun get ->
            {
                username = get.Required.Field "username" Decode.string
                password = get.Required.Field "password" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "username", Encode.string value.username
                "password", Encode.string value.password
            ]

type UserId =
    {
        value: string
    }

    static member Decoder: Decoder<UserId> =
        Decode.object (fun get ->
            {
                value = get.Required.Field "value" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "value", Encode.string value.value
            ]

type Channel =
    {
        name: string
        ``private``: bool
    }

    static member Decoder: Decoder<Channel> =
        Decode.object (fun get ->
            {
                name = get.Required.Field "name" Decode.string
                ``private`` = get.Required.Field "private" Decode.bool
            }
        )

    static member Encoder value =
        Encode.object
            [
                "name", Encode.string value.name
                "private", Encode.bool value.``private``
            ]

type Email =
    {
        value: string
    }

    static member Decoder: Decoder<Email> =
        Decode.object (fun get ->
            {
                value = get.Required.Field "value" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "value", Encode.string value.value
            ]

type Event =
    | LogIn of LogInData
    | LogOut of UserId
    | JoinChannels of list<Channel>
    | SetEmails of list<Email>

    static member LogInDecoder: Decoder<Event> =
        Decode.object (fun get -> LogIn(get.Required.Field "data" LogInData.Decoder))

    static member LogOutDecoder: Decoder<Event> =
        Decode.object (fun get -> LogOut(get.Required.Field "data" UserId.Decoder))

    static member JoinChannelsDecoder: Decoder<Event> =
        Decode.object (fun get -> JoinChannels(get.Required.Field "data" (Decode.list Channel.Decoder)))

    static member SetEmailsDecoder: Decoder<Event> =
        Decode.object (fun get -> SetEmails(get.Required.Field "data" (Decode.list Email.Decoder)))

    static member Decoder: Decoder<Event> =
        GotynoCoders.decodeWithTypeTag
            "type"
            [|
                "LogIn", Event.LogInDecoder
                "LogOut", Event.LogOutDecoder
                "JoinChannels", Event.JoinChannelsDecoder
                "SetEmails", Event.SetEmailsDecoder
            |]

    static member Encoder =
        function
        | LogIn payload ->
            Encode.object [ "type", Encode.string "LogIn"
                            "data", LogInData.Encoder payload ]

        | LogOut payload ->
            Encode.object [ "type", Encode.string "LogOut"
                            "data", UserId.Encoder payload ]

        | JoinChannels payload ->
            Encode.object [ "type", Encode.string "JoinChannels"
                            "data", GotynoCoders.encodeList Channel.Encoder payload ]

        | SetEmails payload ->
            Encode.object [ "type", Encode.string "SetEmails"
                            "data", GotynoCoders.encodeList Email.Encoder payload ]

type Either<'l, 'r> =
    | Left of 'l
    | Right of 'r

    static member LeftDecoder decodeL: Decoder<Either<'l, 'r>> =
        Decode.object (fun get -> Left(get.Required.Field "data" decodeL))

    static member RightDecoder decodeR: Decoder<Either<'l, 'r>> =
        Decode.object (fun get -> Right(get.Required.Field "data" decodeR))

    static member Decoder decodeL decodeR: Decoder<Either<'l, 'r>> =
        GotynoCoders.decodeWithTypeTag
            "type"
            [|
                "Left", Either.LeftDecoder decodeL
                "Right", Either.RightDecoder decodeR
            |]

    static member Encoder encodeL encodeR =
        function
        | Left payload ->
            Encode.object [ "type", Encode.string "Left"
                            "data", encodeL payload ]

        | Right payload ->
            Encode.object [ "type", Encode.string "Right"
                            "data", encodeR payload ]

type StillSize =
    | W92
    | W185
    | W300
    | H632
    | Original

    static member Decoder: Decoder<StillSize> =
        GotynoCoders.decodeOneOf Decode.string [|"w92", W92; "w185", W185; "w300", W300; "h632", H632; "original", Original|]

    static member Encoder =
        function
        | W92 -> Encode.string "w92"
        | W185 -> Encode.string "w185"
        | W300 -> Encode.string "w300"
        | H632 -> Encode.string "h632"
        | Original -> Encode.string "original"

type BackdropSize =
    | W300
    | W780
    | W1280
    | Original

    static member Decoder: Decoder<BackdropSize> =
        GotynoCoders.decodeOneOf Decode.string [|"w300", W300; "w780", W780; "w1280", W1280; "original", Original|]

    static member Encoder =
        function
        | W300 -> Encode.string "w300"
        | W780 -> Encode.string "w780"
        | W1280 -> Encode.string "w1280"
        | Original -> Encode.string "original"

type ImageConfigurationData =
    {
        base_url: string
        secure_base_url: string
        still_sizes: list<StillSize>
        backdrop_sizes: list<BackdropSize>
    }

    static member Decoder: Decoder<ImageConfigurationData> =
        Decode.object (fun get ->
            {
                base_url = get.Required.Field "base_url" Decode.string
                secure_base_url = get.Required.Field "secure_base_url" Decode.string
                still_sizes = get.Required.Field "still_sizes" (Decode.list StillSize.Decoder)
                backdrop_sizes = get.Required.Field "backdrop_sizes" (Decode.list BackdropSize.Decoder)
            }
        )

    static member Encoder value =
        Encode.object
            [
                "base_url", Encode.string value.base_url
                "secure_base_url", Encode.string value.secure_base_url
                "still_sizes", GotynoCoders.encodeList StillSize.Encoder value.still_sizes
                "backdrop_sizes", GotynoCoders.encodeList BackdropSize.Encoder value.backdrop_sizes
            ]

type ConfigurationData =
    {
        images: ImageConfigurationData
        change_keys: list<string>
    }

    static member Decoder: Decoder<ConfigurationData> =
        Decode.object (fun get ->
            {
                images = get.Required.Field "images" ImageConfigurationData.Decoder
                change_keys = get.Required.Field "change_keys" (Decode.list Decode.string)
            }
        )

    static member Encoder value =
        Encode.object
            [
                "images", ImageConfigurationData.Encoder value.images
                "change_keys", GotynoCoders.encodeList Encode.string value.change_keys
            ]

type KnownForMovie =
    {
        media_type: string
        poster_path: option<string>
        id: uint32
        title: option<string>
        vote_average: float32
        release_date: option<string>
        overview: string
    }

    static member Decoder: Decoder<KnownForMovie> =
        Decode.object (fun get ->
            {
                media_type = get.Required.Field "media_type" (GotynoCoders.decodeLiteralString "movie")
                poster_path = get.Optional.Field "poster_path" Decode.string
                id = get.Required.Field "id" Decode.uint32
                title = get.Optional.Field "title" Decode.string
                vote_average = get.Required.Field "vote_average" Decode.float32
                release_date = get.Optional.Field "release_date" Decode.string
                overview = get.Required.Field "overview" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "media_type", Encode.string "movie"
                "poster_path", (Encode.option Encode.string value.poster_path)
                "id", Encode.uint32 value.id
                "title", (Encode.option Encode.string value.title)
                "vote_average", Encode.float32 value.vote_average
                "release_date", (Encode.option Encode.string value.release_date)
                "overview", Encode.string value.overview
            ]

type KnownForShow =
    {
        media_type: string
        poster_path: option<string>
        id: uint32
        vote_average: float32
        overview: string
        first_air_date: option<string>
        name: option<string>
    }

    static member Decoder: Decoder<KnownForShow> =
        Decode.object (fun get ->
            {
                media_type = get.Required.Field "media_type" (GotynoCoders.decodeLiteralString "tv")
                poster_path = get.Optional.Field "poster_path" Decode.string
                id = get.Required.Field "id" Decode.uint32
                vote_average = get.Required.Field "vote_average" Decode.float32
                overview = get.Required.Field "overview" Decode.string
                first_air_date = get.Optional.Field "first_air_date" Decode.string
                name = get.Optional.Field "name" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "media_type", Encode.string "tv"
                "poster_path", (Encode.option Encode.string value.poster_path)
                "id", Encode.uint32 value.id
                "vote_average", Encode.float32 value.vote_average
                "overview", Encode.string value.overview
                "first_air_date", (Encode.option Encode.string value.first_air_date)
                "name", (Encode.option Encode.string value.name)
            ]

type KnownFor =
    | KnownForKnownForShow of KnownForShow
    | KnownForKnownForMovie of KnownForMovie
    | KnownForString of string
    | KnownForF32 of float32

    static member KnownForKnownForShowDecoder: Decoder<KnownFor> =
        Decode.map KnownForKnownForShow KnownForShow.Decoder

    static member KnownForKnownForMovieDecoder: Decoder<KnownFor> =
        Decode.map KnownForKnownForMovie KnownForMovie.Decoder

    static member KnownForStringDecoder: Decoder<KnownFor> =
        Decode.map KnownForString Decode.string

    static member KnownForF32Decoder: Decoder<KnownFor> =
        Decode.map KnownForF32 Decode.float32

    static member Decoder: Decoder<KnownFor> =
        Decode.oneOf
            [
                KnownFor.KnownForKnownForShowDecoder
                KnownFor.KnownForKnownForMovieDecoder
                KnownFor.KnownForStringDecoder
                KnownFor.KnownForF32Decoder
            ]

    static member Encoder =
        function
        | KnownForKnownForShow payload ->
            KnownForShow.Encoder payload

        | KnownForKnownForMovie payload ->
            KnownForMovie.Encoder payload

        | KnownForString payload ->
            Encode.string payload

        | KnownForF32 payload ->
            Encode.float32 payload

type KnownForMovieWithoutTypeTag =
    {
        poster_path: option<string>
        id: uint32
        title: option<string>
        vote_average: float32
        release_date: option<string>
        overview: string
    }

    static member Decoder: Decoder<KnownForMovieWithoutTypeTag> =
        Decode.object (fun get ->
            {
                poster_path = get.Optional.Field "poster_path" Decode.string
                id = get.Required.Field "id" Decode.uint32
                title = get.Optional.Field "title" Decode.string
                vote_average = get.Required.Field "vote_average" Decode.float32
                release_date = get.Optional.Field "release_date" Decode.string
                overview = get.Required.Field "overview" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "poster_path", (Encode.option Encode.string value.poster_path)
                "id", Encode.uint32 value.id
                "title", (Encode.option Encode.string value.title)
                "vote_average", Encode.float32 value.vote_average
                "release_date", (Encode.option Encode.string value.release_date)
                "overview", Encode.string value.overview
            ]

type KnownForShowWithoutTypeTag =
    {
        poster_path: option<string>
        id: uint32
        vote_average: float32
        overview: string
        first_air_date: option<string>
        name: option<string>
    }

    static member Decoder: Decoder<KnownForShowWithoutTypeTag> =
        Decode.object (fun get ->
            {
                poster_path = get.Optional.Field "poster_path" Decode.string
                id = get.Required.Field "id" Decode.uint32
                vote_average = get.Required.Field "vote_average" Decode.float32
                overview = get.Required.Field "overview" Decode.string
                first_air_date = get.Optional.Field "first_air_date" Decode.string
                name = get.Optional.Field "name" Decode.string
            }
        )

    static member Encoder value =
        Encode.object
            [
                "poster_path", (Encode.option Encode.string value.poster_path)
                "id", Encode.uint32 value.id
                "vote_average", Encode.float32 value.vote_average
                "overview", Encode.string value.overview
                "first_air_date", (Encode.option Encode.string value.first_air_date)
                "name", (Encode.option Encode.string value.name)
            ]

type KnownForEmbedded =
    | Movie of KnownForMovieWithoutTypeTag
    | TV of KnownForShowWithoutTypeTag

    static member MovieDecoder: Decoder<KnownForEmbedded> =
        Decode.object (fun get ->
            Movie {
                poster_path = get.Optional.Field "poster_path" Decode.string
                id = get.Required.Field "id" Decode.uint32
                title = get.Optional.Field "title" Decode.string
                vote_average = get.Required.Field "vote_average" Decode.float32
                release_date = get.Optional.Field "release_date" Decode.string
                overview = get.Required.Field "overview" Decode.string
            }
        )

    static member TVDecoder: Decoder<KnownForEmbedded> =
        Decode.object (fun get ->
            TV {
                poster_path = get.Optional.Field "poster_path" Decode.string
                id = get.Required.Field "id" Decode.uint32
                vote_average = get.Required.Field "vote_average" Decode.float32
                overview = get.Required.Field "overview" Decode.string
                first_air_date = get.Optional.Field "first_air_date" Decode.string
                name = get.Optional.Field "name" Decode.string
            }
        )

    static member Decoder: Decoder<KnownForEmbedded> =
        GotynoCoders.decodeWithTypeTag
            "media_type"
            [|
                "Movie", KnownForEmbedded.MovieDecoder
                "TV", KnownForEmbedded.TVDecoder
            |]

    static member Encoder =
        function
        | Movie payload ->
            Encode.object
                [
                    "media_type", Encode.string "Movie"
                    "poster_path", (Encode.option Encode.string payload.poster_path)
                    "id", Encode.uint32 payload.id
                    "title", (Encode.option Encode.string payload.title)
                    "vote_average", Encode.float32 payload.vote_average
                    "release_date", (Encode.option Encode.string payload.release_date)
                    "overview", Encode.string payload.overview
                ]

        | TV payload ->
            Encode.object
                [
                    "media_type", Encode.string "TV"
                    "poster_path", (Encode.option Encode.string payload.poster_path)
                    "id", Encode.uint32 payload.id
                    "vote_average", Encode.float32 payload.vote_average
                    "overview", Encode.string payload.overview
                    "first_air_date", (Encode.option Encode.string payload.first_air_date)
                    "name", (Encode.option Encode.string payload.name)
                ]