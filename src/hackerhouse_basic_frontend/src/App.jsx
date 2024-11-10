import React, { useState, useEffect } from "react";
import NfidLogin from "./components/NfidLogin";
import "./App.scss"; // Import the CSS file for styling

function App() {
  const [backendActor, setBackendActor] = useState();
  const [userId, setUserId] = useState();
  const [userName, setUserName] = useState();
  const [userResults, setUserResults] = useState([]);
  const [sentimentInput, setSentimentInput] = useState("");
  const [sentimentResult, setSentimentResult] = useState("");

  // Fetch user profile when backendActor becomes available
  useEffect(() => {
    if (backendActor) {
      backendActor.getUserProfile().then((response) => {
        if (response.ok) {
          setUserId(response.ok.id.toString());
          setUserName(response.ok.name);
        }
      });
    }
  }, [backendActor]);

  // Handle setting user profile
  const handleSubmitUserProfile = (event) => {
    event.preventDefault();
    const name = event.target.elements.name.value;
    backendActor.setUserProfile(name).then((response) => {
      if (response.ok) {
        setUserId(response.ok.id.toString());
        setUserName(response.ok.name);
      } else if (response.err) {
        alert("Error: " + response.err);
      }
    });
  };

  // Handle adding a user result
  const handleAddUserResult = (event) => {
    event.preventDefault();
    const result = event.target.elements.result.value;
    backendActor.addUserResult(result).then((response) => {
      if (response.ok) {
        setUserResults(response.ok.results);
        event.target.reset();
      } else if (response.err) {
        alert("Error: " + response.err);
      }
    });
  };

  // Handle fetching user results
  const handleGetUserResults = () => {
    backendActor.getUserResults().then((response) => {
      if (response.ok) {
        setUserResults(response.ok.results);
      } else if (response.err) {
        alert("Error: " + response.err);
      }
    });
  };

  // Handle sentiment analysis
  const handleSentimentAnalysis = (event) => {
    event.preventDefault();
    backendActor
      .outcall_ai_model_for_sentiment_analysis(sentimentInput)
      .then((response) => {
        if (response.ok) {
          setSentimentResult(response.ok.result);
          // Optionally, add the result to user results
          backendActor.addUserResult(response.ok.result).then((res) => {
            if (res.ok) {
              setUserResults(res.ok.results);
            }
          });
        } else if (response.err) {
          alert("Error: " + response.err);
        }
      });
  };

  return (
    <main>
      <img src="/logo2.svg" alt="DFINITY logo" />
      <h1>Welcome to IC AI Hacker House!</h1>
      {!backendActor && (
        <section id="nfid-section">
          <NfidLogin setBackendActor={setBackendActor}></NfidLogin>
        </section>
      )}
      {backendActor && (
        <div className="container">
          {/* User Profile Section */}
          <section className="profile-section">
            <h2>User Profile</h2>
            <form onSubmit={handleSubmitUserProfile}>
              <label htmlFor="name">Enter your name:</label>
              <input id="name" name="name" type="text" required />
              <button type="submit">Save</button>
            </form>
            {userId && (
              <p>
                <strong>User ID:</strong> {userId}
              </p>
            )}
            {userName && (
              <p>
                <strong>User Name:</strong> {userName}
              </p>
            )}
          </section>

          {/* Sentiment Analysis Section */}
          <section className="sentiment-section">
            <h2>Sentiment Analysis</h2>
            <form onSubmit={handleSentimentAnalysis}>
              <label htmlFor="sentimentInput">Enter text:</label>
              <textarea
                id="sentimentInput"
                value={sentimentInput}
                onChange={(e) => setSentimentInput(e.target.value)}
                required
              ></textarea>
              <button type="submit">Analyze</button>
            </form>
            {sentimentResult && (
              <p>
                <strong>Analysis Result:</strong> {sentimentResult}
              </p>
            )}
          </section>

          {/* User Results Section */}
          <section className="results-section">
            <h2>User Results</h2>
            <form onSubmit={handleAddUserResult}>
              <label htmlFor="result">Add a result:</label>
              <input id="result" name="result" type="text" required />
              <button type="submit">Add Result</button>
            </form>
            <button onClick={handleGetUserResults}>Refresh Results</button>
            {userResults.length > 0 && (
              <ul>
                {userResults.map((result, index) => (
                  <li key={index}>{result}</li>
                ))}
              </ul>
            )}
          </section>
        </div>
      )}
    </main>
  );
}

export default App;
