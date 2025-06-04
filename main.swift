import Foundation
// For URLSession, URLRequest etc. on Linux or some command-line setups
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// @main // Removed @main attribute
struct MastermindGame {

    // MARK: - Nested API Data Structures (Codable)
    struct CreateGameResponse: Codable {
        let game_id: String
    }

    struct GuessRequest: Codable {
        let game_id: String
        let guess: String
    }

    struct GuessResponse: Codable {
        let black: Int
        let white: Int
    }

    struct APIErrorResponse: Codable, Error {
        let error: String
    }

    // MARK: - Nested API Client
    enum NetworkError: Error {
        case invalidURL
        case requestFailed(Error)
        case noData
        case decodingError(Error)
        case apiError(String, Int) // Message, StatusCode
        case unexpectedStatusCode(Int)
    }

    actor MastermindAPIClient {
        private let baseURLString: String
        private let session: URLSession

        init(baseURLString: String) {
            self.baseURLString = baseURLString
            self.session = URLSession(configuration: .default)
        }

        private func performRequest<T: Decodable>(endpoint: String, method: String, body: Data? = nil, expectedStatusCode: Int) async throws -> T {
            guard let url = URL(string: baseURLString + endpoint) else {
                throw MastermindGame.NetworkError.invalidURL // Use Self.NetworkError or MastermindGame.NetworkError
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MastermindGame.NetworkError.requestFailed(URLError(.badServerResponse))
            }
            
            if httpResponse.statusCode != expectedStatusCode {
                if !data.isEmpty, let apiError = try? JSONDecoder().decode(MastermindGame.APIErrorResponse.self, from: data) { // Use Self.APIErrorResponse
                    throw MastermindGame.NetworkError.apiError(apiError.error, httpResponse.statusCode)
                }
                throw MastermindGame.NetworkError.unexpectedStatusCode(httpResponse.statusCode)
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                return decodedResponse
            } catch {
                print("Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Received JSON: \(jsonString)")
                }
                throw MastermindGame.NetworkError.decodingError(error)
            }
        }

        private func performRequestNoContent(endpoint: String, method: String, expectedStatusCode: Int) async throws {
            guard let url = URL(string: baseURLString + endpoint) else {
                throw MastermindGame.NetworkError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = method

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MastermindGame.NetworkError.requestFailed(URLError(.badServerResponse))
            }

            if httpResponse.statusCode != expectedStatusCode {
                if !data.isEmpty, let apiError = try? JSONDecoder().decode(MastermindGame.APIErrorResponse.self, from: data) {
                     throw MastermindGame.NetworkError.apiError(apiError.error, httpResponse.statusCode)
                }
                throw MastermindGame.NetworkError.unexpectedStatusCode(httpResponse.statusCode)
            }
        }

        func createGame() async throws -> String {
            // Note: Since CreateGameResponse is now nested, ensure performRequest can decode it.
            // If T is MastermindGame.CreateGameResponse, it should work.
            let response: MastermindGame.CreateGameResponse = try await performRequest(endpoint: "/game", method: "POST", expectedStatusCode: 200)
            return response.game_id
        }

        func makeGuess(gameID: String, guess: String) async throws -> MastermindGame.GuessResponse {
            let requestBody = MastermindGame.GuessRequest(game_id: gameID, guess: guess)
            guard let bodyData = try? JSONEncoder().encode(requestBody) else {
                throw MastermindGame.NetworkError.requestFailed(NSError(domain: "EncodingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode GuessRequest"]))
            }
            return try await performRequest(endpoint: "/guess", method: "POST", body: bodyData, expectedStatusCode: 200)
        }

        func deleteGame(gameID: String) async throws {
            try await performRequestNoContent(endpoint: "/game/\(gameID)", method: "DELETE", expectedStatusCode: 204)
        }
    }


    // MARK: - Configuration Constants
    static let API_BASE_URL = "https://mastermind.darkube.app"
    static let MAX_ATTEMPTS = 10
    static let CODE_LENGTH = 4
    static let MIN_DIGIT = 1
    static let MAX_DIGIT = 6

    // Initialize apiClient as a static property
    static let apiClient = MastermindAPIClient(baseURLString: Self.API_BASE_URL) // This now refers to the nested MastermindAPIClient

    // MARK: - Game Logic & UI
    static func printWelcome() {
        print("------------------------------------")
        print("    🧠 Welcome to Mastermind! 🧠")
        print("------------------------------------")
        print("Try to guess the secret \(Self.CODE_LENGTH)-digit code.")
        print("Each digit is between \(Self.MIN_DIGIT) and \(Self.MAX_DIGIT).")
        print("Feedback: B (Black) = correct digit, correct position.")
        print("          W (White) = correct digit, wrong position.")
        print("Type 'exit' at any time to quit.")
        print("------------------------------------")
    }

    static func promptForGuess(attempt: Int) -> String? {
        while true {
            print("\nAttempt \(attempt)/\(Self.MAX_ATTEMPTS). Enter your \(Self.CODE_LENGTH)-digit guess (e.g., 1234):")
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return "exit" 
            }

            if input == "exit" {
                return "exit"
            }

            guard input.count == Self.CODE_LENGTH else {
                print("Invalid input: Guess must be \(Self.CODE_LENGTH) digits long.")
                continue
            }

            var isValidGuess = true
            for char in input {
                guard let digit = Int(String(char)) else {
                    print("Invalid input: '\(char)' is not a digit.")
                    isValidGuess = false
                    break
                }
                guard (Self.MIN_DIGIT...Self.MAX_DIGIT).contains(digit) else { 
                    print("Invalid input: Digit '\(digit)' must be between \(Self.MIN_DIGIT) and \(Self.MAX_DIGIT).")
                    isValidGuess = false
                    break
                }
            }

            if isValidGuess {
                return input
            }
        }
    }

    static func playGame(apiClient: MastermindAPIClient) async { // Parameter type is now MastermindGame.MastermindAPIClient
        print("\nStarting a new game...")
        var gameID: String? 

        do {
            let newGameID = try await apiClient.createGame()
            gameID = newGameID 
            print("🎉 New game started! Game ID: \(newGameID)")
            print("Let the guessing begin!")

            var gameWon = false
            for attempt in 1...Self.MAX_ATTEMPTS { 
                guard let guess = Self.promptForGuess(attempt: attempt) else { 
                    print("An unexpected error occurred while reading your guess.")
                    break 
                }

                if guess == "exit" {
                    print("Exiting game as requested.")
                    break 
                }

                do {
                    let feedback = try await apiClient.makeGuess(gameID: newGameID, guess: guess)
                    print("➡️ Your guess: \(guess) -> Feedback: \(String(repeating: "B", count: feedback.black))\(String(repeating: "W", count: feedback.white))")

                    if feedback.black == Self.CODE_LENGTH { 
                        print("\n🏆 Congratulations! You guessed the code \(guess) in \(attempt) attempts! 🎉")
                        gameWon = true
                        break 
                    }
                } catch let MastermindGame.NetworkError.apiError(message, statusCode) { // Catch specific nested error
                     print("🚨 API Error (\(statusCode)): \(message). Please check your guess or try again.")
                     if statusCode == 404 { 
                        print("The game session might have expired or is invalid. Please start a new game.")
                        return 
                     }
                } catch {
                    print("🚨 An error occurred while submitting your guess: \(error.localizedDescription)")
                }
            }

            if !gameWon && gameID != nil { 
                print("\n😕 Game Over! You've used all \(Self.MAX_ATTEMPTS) attempts.") 
                print("Better luck next time!")
            }

        } catch let MastermindGame.NetworkError.apiError(message, statusCode) { // Catch specific nested error
            print("🚨 Failed to start game. API Error (\(statusCode)): \(message)")
        } catch {
            print("🚨 Failed to start or play game: \(error.localizedDescription)")
        }

        if let id = gameID {
            print("\nCleaning up game session (ID: \(id))...")
            do {
                try await apiClient.deleteGame(gameID: id)
                print("Game session deleted successfully.")
            } catch {
                print("⚠️ Could not delete game session (ID: \(id)): \(error.localizedDescription). It might auto-expire on the server.")
            }
        }
    }

    static func main() async {
        Self.printWelcome() 

        mainLoop: while true {
            print("\nChoose an action:")
            print("1. Play Mastermind")
            print("2. Exit")
            print("Enter your choice (1 or 2):")

            guard let choice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                print("\nNo input received, exiting.")
                break mainLoop
            }

            switch choice {
            case "1":
                await Self.playGame(apiClient: Self.apiClient) 
            case "2", "exit":
                print("\n👋 Thanks for playing Mastermind! Goodbye.")
                break mainLoop
            default:
                print("Invalid choice. Please enter 1 or 2.")
            }
            print("\n------------------------------------")
        }
        exit(0) 
    }
}

// Explicitly call the main function to start the application.
// Create a Task to run the async main function.
Task.detached {
    await MastermindGame.main()
}

// Keep the main thread alive for the Task to complete.
// MastermindGame.main() calls exit(0), which will terminate this.
dispatchMain()