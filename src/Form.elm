module Form exposing (..)

import DataSource exposing (DataSource)
import Date exposing (Date)
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Json.Encode as Encode
import List.Extra
import List.NonEmpty
import Server.Request as Request exposing (Request)


type Form value view
    = Form
        -- TODO either make this a Dict and include the client-side validations here
        -- OR create a new Dict with ( name => client-side validation ( name -> Result String () )
        (List
            ( List (FieldInfoSimple view)
            , List view -> List view
            )
        )
        (Request (Result String value))
        (Request
            (DataSource
                (List
                    ( String
                    , { errors : List String
                      , raw : Maybe String
                      }
                    )
                )
            )
        )
        (Model -> Result (List String) value)


type Field value view
    = Field (FieldInfo value view)


type alias FieldInfoSimple view =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List String)
    , toHtml :
        FinalFieldInfo
        -> Maybe { raw : Maybe String, errors : List String }
        -> view
    , properties : List ( String, Encode.Value )
    , clientValidations : Maybe String -> Result String ()
    }


type alias FieldInfo value view =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List String)
    , toHtml :
        FinalFieldInfo
        -> Maybe { raw : Maybe String, errors : List String }
        -> view
    , decode : Maybe String -> Result String value
    , properties : List ( String, Encode.Value )
    }


type alias FinalFieldInfo =
    { name : String
    , initialValue : Maybe String
    , type_ : String
    , required : Bool
    , serverValidation : Maybe String -> DataSource (List String)
    , properties : List ( String, Encode.Value )
    }


succeed : constructor -> Form constructor view
succeed constructor =
    Form []
        (Request.succeed (Ok constructor))
        (Request.succeed (DataSource.succeed []))
        (\_ -> Ok constructor)


runClientValidations : Model -> Form value view -> Result (List String) value
runClientValidations model (Form fields decoder serverValidations modelToValue) =
    modelToValue model


type Msg
    = OnFieldInput { name : String, value : String }
    | OnFieldFocus { name : String }
    | OnBlur


type alias Model =
    Dict String { raw : Maybe String, errors : List String }


runValidation : Form value view -> { name : String, value : String } -> List String
runValidation (Form fields decoder serverValidations modelToValue) newInput =
    let
        matchingDecoder : Maybe (FieldInfoSimple view)
        matchingDecoder =
            fields
                |> List.Extra.findMap
                    (\( fields_, _ ) ->
                        List.Extra.findMap
                            (\field ->
                                if field.name == newInput.name then
                                    Just field

                                else
                                    Nothing
                            )
                            fields_
                    )
    in
    case matchingDecoder of
        Just decoder_ ->
            case decoder_.clientValidations (Just newInput.value) of
                Ok () ->
                    []

                Err error ->
                    [ error ]

        Nothing ->
            []


update : Form value view -> Msg -> Model -> Model
update form msg model =
    case msg of
        OnFieldInput { name, value } ->
            -- TODO run client-side validations
            model
                |> Dict.update name
                    (\entry ->
                        case entry of
                            Just { raw, errors } ->
                                -- TODO calculate errors here?
                                Just { raw = Just value, errors = runValidation form { name = name, value = value } }

                            Nothing ->
                                -- TODO calculate errors here?
                                Just { raw = Just value, errors = [] }
                    )

        OnFieldFocus record ->
            model

        OnBlur ->
            model


init : Model
init =
    Dict.empty


toInputRecord :
    String
    -> Maybe String
    -> Maybe { raw : Maybe String, errors : List String }
    -> FinalFieldInfo
    ->
        { toInput : List (Html.Attribute Msg)
        , toLabel : List (Html.Attribute Msg)
        , errors : List String
        }
toInputRecord name maybeValue info field =
    { toInput =
        ([ Attr.name name |> Just
         , maybeValue
            |> Maybe.withDefault name
            |> Attr.id
            |> Just
         , case ( maybeValue, info ) of
            ( Just value, _ ) ->
                Attr.value value |> Just

            ( _, Just { raw } ) ->
                valueAttr field raw

            _ ->
                valueAttr field field.initialValue
         , field.type_ |> Attr.type_ |> Just
         , field.required |> Attr.required |> Just
         , if field.type_ == "checkbox" then
            Html.Events.onCheck
                (\checkState ->
                    OnFieldInput
                        { name = name
                        , value =
                            if checkState then
                                "on"

                            else
                                ""
                        }
                )
                |> Just

           else
            Html.Events.onInput
                (\newValue ->
                    OnFieldInput
                        { name = name, value = newValue }
                )
                |> Just
         ]
            |> List.filterMap identity
        )
            ++ toHtmlProperties field.properties
    , toLabel =
        [ maybeValue
            |> Maybe.withDefault name
            |> Attr.for
        ]
    , errors = info |> Maybe.map .errors |> Maybe.withDefault []
    }


toHtmlProperties : List ( String, Encode.Value ) -> List (Html.Attribute msg)
toHtmlProperties properties =
    properties
        |> List.map
            (\( key, value ) ->
                Attr.property key value
            )


toRadioInputRecord :
    String
    -> String
    -> Maybe { raw : Maybe String, errors : List String }
    -> FinalFieldInfo
    ->
        { toInput : List (Html.Attribute Msg)
        , toLabel : List (Html.Attribute Msg)
        , errors : List String
        }
toRadioInputRecord name itemValue info field =
    { toInput =
        ([ Attr.name name |> Just
         , itemValue
            |> Attr.id
            |> Just
         , Attr.value itemValue |> Just
         , field.type_ |> Attr.type_ |> Just
         , field.required |> Attr.required |> Just
         , if (info |> Maybe.andThen .raw) == Just itemValue then
            Attr.attribute "checked" "true" |> Just

           else
            Nothing
         , Html.Events.onCheck
            (\checkState ->
                OnFieldInput
                    { name = name
                    , value =
                        if checkState then
                            itemValue

                        else
                            ""
                    }
            )
            |> Just
         ]
            |> List.filterMap identity
        )
            ++ toHtmlProperties field.properties
    , toLabel =
        [ itemValue |> Attr.for
        ]
    , errors = info |> Maybe.map .errors |> Maybe.withDefault []
    }


valueAttr field stringValue =
    if field.type_ == "checkbox" then
        if stringValue == Just "on" then
            Attr.attribute "checked" "true" |> Just

        else
            Nothing

    else
        stringValue |> Maybe.map Attr.value


text :
    String
    ->
        ({ toInput : List (Html.Attribute Msg)
         , toLabel : List (Html.Attribute Msg)
         , errors : List String
         }
         -> view
        )
    -> Field String view
text name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "text"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                toHtmlFn (toInputRecord name Nothing info fieldInfo)

        -- TODO should it be Err if Nothing?
        , decode = Maybe.withDefault "" >> Ok
        , properties = []
        }


hidden :
    String
    -> String
    -> (List (Html.Attribute Msg) -> view)
    -> Field String view
hidden name value toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "hidden"
        , required = False

        -- TODO shouldn't be possible to include any server-side validations on hidden fields
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                -- TODO shouldn't be possible to add any validations or chain anything
                toHtmlFn (toInputRecord name Nothing info fieldInfo |> .toInput)

        -- TODO should it be Err if Nothing?
        , decode = Maybe.withDefault "" >> Ok
        , properties = []
        }


radio :
    String
    -> ( ( String, item ), List ( String, item ) )
    ->
        (item
         ->
            { toInput : List (Html.Attribute Msg)
            , toLabel : List (Html.Attribute Msg)
            , errors : List String

            -- TODO
            --, item : item
            }
         -> view
        )
    -> (List view -> view)
    -> Field (Maybe item) view
radio name nonEmptyItemMapping toHtmlFn wrapFn =
    let
        itemMapping : List ( String, item )
        itemMapping =
            nonEmptyItemMapping
                |> List.NonEmpty.toList

        toString : item -> String
        toString targetItem =
            case nonEmptyItemMapping |> List.NonEmpty.toList |> List.filter (\( string, item ) -> item == targetItem) |> List.head of
                Just ( string, _ ) ->
                    string

                Nothing ->
                    "Missing enum"

        fromString : String -> Maybe item
        fromString string =
            itemMapping
                |> Dict.fromList
                |> Dict.get string

        items : List item
        items =
            itemMapping
                |> List.map Tuple.second
    in
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "radio"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            -- TODO use `toString` to set value
            \fieldInfo info ->
                items
                    |> List.map (\item -> toHtmlFn item (toRadioInputRecord name (toString item) info fieldInfo))
                    |> wrapFn

        -- TODO should it be Err if Nothing?
        , decode =
            \raw ->
                raw
                    |> Maybe.andThen fromString
                    |> Ok
        , properties = []
        }



{-
       List.foldl
           (\item formSoFar ->
               required (rawRadio name toHtmlFn fromString)
                   formSoFar
           )
           (succeed Nothing)
           items


   rawRadio name toHtmlFn fromString =

-}


submit :
    ({ attrs : List (Html.Attribute Msg)
     }
     -> view
    )
    -> Field () view
submit toHtmlFn =
    Field
        { name = ""
        , initialValue = Nothing
        , type_ = "submit"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                toHtmlFn
                    { attrs =
                        [ Attr.type_ "submit" ]
                    }
        , decode = \_ -> Ok ()
        , properties = []
        }


view :
    view
    -> Field () view
view viewFn =
    Field
        { name = ""
        , initialValue = Nothing
        , type_ = "submit"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                viewFn
        , decode = \_ -> Ok ()
        , properties = []
        }


number :
    String
    ->
        ({ toInput : List (Html.Attribute Msg)
         , toLabel : List (Html.Attribute Msg)
         , errors : List String
         }
         -> view
        )
    -> Field (Maybe Int) view
number name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "number"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                toHtmlFn (toInputRecord name Nothing info fieldInfo)
        , decode =
            \rawString ->
                rawString
                    |> Maybe.andThen String.toInt
                    |> Ok
        , properties = []
        }


requiredNumber :
    String
    ->
        ({ toInput : List (Html.Attribute Msg)
         , toLabel : List (Html.Attribute Msg)
         , errors : List String
         }
         -> view
        )
    -> Field Int view
requiredNumber name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "number"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                toHtmlFn (toInputRecord name Nothing info fieldInfo)
        , decode =
            \rawString ->
                rawString
                    |> Maybe.andThen String.toInt
                    -- TODO should this be a custom type instead of String error? That way users can customize the error messages
                    |> Result.fromMaybe "Not a valid number"
        , properties = []
        }


date :
    String
    ->
        ({ toInput : List (Html.Attribute Msg)
         , toLabel : List (Html.Attribute Msg)
         , errors : List String
         }
         -> view
        )
    -- TODO should be Date type
    -> Field Date view
date name toHtmlFn =
    Field
        { name = name
        , initialValue = Nothing
        , type_ = "date"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                toHtmlFn (toInputRecord name Nothing info fieldInfo)
        , decode =
            \rawString ->
                rawString
                    |> Maybe.withDefault ""
                    -- TODO should empty string be decoded into Nothing instead of an error?
                    |> Date.fromIsoString
        , properties = []
        }


checkbox :
    String
    -> Bool
    ->
        ({ toInput : List (Html.Attribute Msg)
         , toLabel : List (Html.Attribute Msg)
         , errors : List String
         }
         -> view
        )
    -- TODO should be Date type
    -> Field Bool view
checkbox name initial toHtmlFn =
    Field
        { name = name
        , initialValue =
            if initial then
                Just "on"

            else
                Nothing
        , type_ = "checkbox"
        , required = False
        , serverValidation = \_ -> DataSource.succeed []
        , toHtml =
            \fieldInfo info ->
                toHtmlFn (toInputRecord name Nothing info fieldInfo)
        , decode =
            \rawString ->
                Ok (rawString == Just "on")
        , properties = []
        }


withMin : Int -> Field value view -> Field value view
withMin min field =
    withStringProperty ( "min", String.fromInt min ) field


withMax : Int -> Field value view -> Field value view
withMax max field =
    withStringProperty ( "max", String.fromInt max ) field


withMinDate : Date -> Field value view -> Field value view
withMinDate min field =
    withStringProperty ( "min", Date.toIsoString min ) field


withMaxDate : Date -> Field value view -> Field value view
withMaxDate max field =
    withStringProperty ( "max", Date.toIsoString max ) field


type_ : String -> Field value view -> Field value view
type_ typeName (Field field) =
    Field
        { field | type_ = typeName }


withInitialValue : String -> Field value view -> Field value view
withInitialValue initialValue (Field field) =
    Field { field | initialValue = Just initialValue }


multiple : Field value view -> Field value view
multiple (Field field) =
    Field { field | properties = ( "multiple", Encode.bool True ) :: field.properties }


withStringProperty : ( String, String ) -> Field value view -> Field value view
withStringProperty ( key, value ) (Field field) =
    Field { field | properties = ( key, Encode.string value ) :: field.properties }


withBoolProperty : ( String, Bool ) -> Field value view -> Field value view
withBoolProperty ( key, value ) (Field field) =
    Field { field | properties = ( key, Encode.bool value ) :: field.properties }


required : Field value view -> Field value view
required (Field field) =
    Field { field | required = True }


telephone : Field value view -> Field value view
telephone (Field field) =
    Field { field | type_ = "tel" }


range : Field value view -> Field value view
range (Field field) =
    Field { field | type_ = "range" }


search : Field value view -> Field value view
search (Field field) =
    Field { field | type_ = "search" }


password : Field value view -> Field value view
password (Field field) =
    Field { field | type_ = "password" }


email : Field value view -> Field value view
email (Field field) =
    Field { field | type_ = "email" }


url : Field value view -> Field value view
url (Field field) =
    Field { field | type_ = "url" }


withServerValidation : (value -> DataSource (List String)) -> Field value view -> Field value view
withServerValidation serverValidation (Field field) =
    Field
        { field
            | serverValidation =
                \value ->
                    case value |> field.decode of
                        Ok decoded ->
                            serverValidation decoded

                        Err error ->
                            DataSource.fail <| "Could not decode form data: " ++ error
        }


withClientValidation : (value -> Result String mapped) -> Field value view -> Field mapped view
withClientValidation mapFn (Field field) =
    Field
        { name = field.name
        , initialValue = field.initialValue
        , type_ = field.type_
        , required = field.required
        , serverValidation = field.serverValidation
        , toHtml = field.toHtml
        , decode =
            \value ->
                value
                    |> field.decode
                    |> Result.andThen mapFn
        , properties = field.properties
        }


with : Field value view -> Form (value -> form) view -> Form form view
with (Field field) (Form fields decoder serverValidations modelToValue) =
    let
        thing : Request (DataSource (List ( String, { raw : Maybe String, errors : List String } )))
        thing =
            Request.map2
                (\arg1 arg2 ->
                    arg1
                        |> DataSource.map2 (::)
                            (field.serverValidation arg2
                                |> DataSource.map
                                    (\validationErrors ->
                                        ( field.name
                                        , { errors = validationErrors
                                          , raw = arg2
                                          }
                                        )
                                    )
                            )
                )
                serverValidations
                (Request.optionalFormField_ field.name)
    in
    Form
        (addField field fields)
        (Request.map2
            (Result.map2 (|>))
            (Request.optionalFormField_ field.name |> Request.map field.decode)
            decoder
        )
        thing
        (\model ->
            let
                maybeValue : Maybe String
                maybeValue =
                    model
                        |> Dict.get field.name
                        |> Maybe.andThen .raw
            in
            case modelToValue model of
                Err error ->
                    Err error

                Ok okSoFar ->
                    maybeValue
                        |> field.decode
                        -- TODO have a `List String` for field validation errors, too
                        |> Result.mapError List.singleton
                        |> Result.andThen (okSoFar >> Ok)
        )


addField : FieldInfo value view -> List ( List (FieldInfoSimple view), List view -> List view ) -> List ( List (FieldInfoSimple view), List view -> List view )
addField field list =
    case list of
        [] ->
            [ ( [ simplify2 field ], identity )
            ]

        ( fields, wrapFn ) :: others ->
            ( simplify2 field :: fields, wrapFn ) :: others


append : Field value view -> Form form view -> Form form view
append (Field field) (Form fields decoder serverValidations modelToValue) =
    Form
        --(field :: fields)
        (addField field fields)
        decoder
        serverValidations
        modelToValue


appendForm : (form1 -> form2 -> form) -> Form form1 view -> Form form2 view -> Form form view
appendForm mapFn (Form fields1 decoder1 serverValidations1 modelToValue1) (Form fields2 decoder2 serverValidations2 modelToValue2) =
    Form
        -- TODO is this ordering correct?
        (fields1 ++ fields2)
        (Request.map2 (Result.map2 mapFn) decoder1 decoder2)
        (Request.map2
            (DataSource.map2 (++))
            serverValidations1
            serverValidations2
        )
        (\model ->
            Result.map2 mapFn
                (modelToValue1 model)
                (modelToValue2 model)
        )


wrap : (List view -> view) -> Form form view -> Form form view
wrap newWrapFn (Form fields decoder serverValidations modelToValue) =
    Form (wrapFields fields newWrapFn) decoder serverValidations modelToValue


wrapFields :
    List
        ( List (FieldInfoSimple view)
        , List view -> List view
        )
    -> (List view -> view)
    ->
        List
            ( List (FieldInfoSimple view)
            , List view -> List view
            )
wrapFields fields newWrapFn =
    case fields of
        [] ->
            [ ( [], newWrapFn >> List.singleton )
            ]

        ( existingFields, wrapFn ) :: others ->
            ( existingFields
            , wrapFn >> newWrapFn >> List.singleton
            )
                :: others


simplify : FieldInfo value view -> FinalFieldInfo
simplify field =
    { name = field.name
    , initialValue = field.initialValue
    , type_ = field.type_
    , required = field.required
    , serverValidation = field.serverValidation
    , properties = field.properties
    }


simplify2 : FieldInfo value view -> FieldInfoSimple view
simplify2 field =
    { name = field.name
    , initialValue = field.initialValue
    , type_ = field.type_
    , required = field.required
    , serverValidation = field.serverValidation
    , toHtml = field.toHtml
    , properties = field.properties
    , clientValidations = \value -> value |> field.decode |> Result.map (\_ -> ())
    }


simplify3 : FieldInfoSimple view -> FinalFieldInfo
simplify3 field =
    { name = field.name
    , initialValue = field.initialValue
    , type_ = field.type_
    , required = field.required
    , serverValidation = field.serverValidation
    , properties = field.properties
    }



{-
   - If there is at least one file field, then use enctype multi-part. Otherwise use form encoding (or maybe GET with query params?).
   - Should it ever use GET forms?
   - Ability to do server-only validations (like uniqueness check with DataSource)
   - Return error messages that can be presented inline from server response (both on full page load and on client-side request)
   - Add functions for built-in form validations
-}


toHtml :
    (List (Html.Attribute msg) -> List view -> view)
    -> Dict String { raw : Maybe String, errors : List String }
    -> Form value view
    -> view
toHtml toForm serverValidationErrors (Form fields decoder serverValidations modelToValue) =
    toForm
        [ Attr.method "POST"
        ]
        (fields
            |> List.reverse
            |> List.concatMap
                (\( nestedFields, wrapFn ) ->
                    nestedFields
                        |> List.reverse
                        |> List.map
                            (\field ->
                                field.toHtml
                                    (simplify3 field)
                                    (serverValidationErrors
                                        |> Dict.get field.name
                                    )
                            )
                        |> wrapFn
                )
        )


toRequest : Form value view -> Request (Result String value)
toRequest (Form fields decoder serverValidations modelToValue) =
    Request.expectFormPost
        (\_ ->
            decoder
        )


toRequest2 :
    Form value view
    ->
        Request
            (DataSource
                (Result Model ( Result String value, Model ))
            )
toRequest2 (Form fields decoder serverValidations modelToValue) =
    Request.map2
        (\decoded errors ->
            errors
                |> DataSource.map
                    (\validationErrors ->
                        if hasErrors validationErrors then
                            validationErrors
                                |> Dict.fromList
                                |> Err

                        else
                            Ok
                                ( decoded
                                , validationErrors
                                    |> Dict.fromList
                                )
                    )
        )
        (Request.expectFormPost
            (\_ ->
                decoder
            )
        )
        (Request.expectFormPost
            (\_ ->
                serverValidations
            )
        )


hasErrors : List ( String, { errors : List String, raw : Maybe String } ) -> Bool
hasErrors validationErrors =
    List.any
        (\( _, entry ) ->
            entry.errors |> List.isEmpty |> not
        )
        validationErrors
