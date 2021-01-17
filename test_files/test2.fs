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
    | Close

    static member LogInDecoder: Decoder<Event> =
        Decode.object (fun get -> LogIn(get.Required.Field "data" LogInData.Decoder))

    static member LogOutDecoder: Decoder<Event> =
        Decode.object (fun get -> LogOut(get.Required.Field "data" UserId.Decoder))

    static member JoinChannelsDecoder: Decoder<Event> =
        Decode.object (fun get -> JoinChannels(get.Required.Field "data" (Decode.list Channel.Decoder)))

    static member SetEmailsDecoder: Decoder<Event> =
        Decode.object (fun get -> SetEmails(get.Required.Field "data" (Decode.list Email.Decoder)))

    static member CloseDecoder: Decoder<Event> =
        Decode.succeed Close

    static member Decoder: Decoder<Event> =
        GotynoCoders.decodeWithTypeTag
            "type"
            [|
                "LogIn", Event.LogInDecoder
                "LogOut", Event.LogOutDecoder
                "JoinChannels", Event.JoinChannelsDecoder
                "SetEmails", Event.SetEmailsDecoder
                "Close", Event.CloseDecoder
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

        | Close ->
            Encode.object [ "type", Encode.string "Close" ]